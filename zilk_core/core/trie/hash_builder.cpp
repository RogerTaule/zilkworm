// Copyright 2026 The Zilkworm Authors (modifications)
// Copyright 2025 The Original Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#include "hash_builder.hpp"

#include <bit>
#include <cstring>
#include <span>

#include <evmone_precompiles/keccak.hpp>
#include <zilk_core/core/common/assert.hpp>
#include <zilk_core/core/common/empty_hashes.hpp>
#include <zilk_core/core/common/endian.hpp>
#include <zilk_core/core/common/util.hpp>
#include <zilk_core/core/rlp/encode.hpp>

namespace silkworm::trie {

// See "Specification: Compact encoding of hex sequence with optional terminator"
// at https://eth.wiki/fundamentals/patricia-tree
//
// Writes the HP-encoded path into `out` (caller-provided buffer, at
// least 33 bytes). Returns the number of bytes written. Avoids the
// heap allocation the old `Bytes` return value triggered — encode_path
// is called per leaf/ext node, hundreds of times per block.
static size_t encode_path(uint8_t* out, ByteView nibbles, bool terminating) noexcept {
    const size_t size = nibbles.size() / 2 + 1;
    const bool odd = (nibbles.size() & 1u) != 0;

    out[0] = static_cast<uint8_t>((terminating ? 0x20 : 0x00) | (odd ? 0x10 : 0x00));

    if (odd) {
        out[0] |= nibbles[0];
        nibbles.remove_prefix(1);
    }

    for (size_t i = 1; i < size; ++i) {
        out[i] = static_cast<uint8_t>((nibbles[0] << 4) | (nibbles[1] & 0x0F));
        nibbles.remove_prefix(2);
    }

    return size;
}

// Raw-pointer-write RLP helpers. The generic `rlp::encode(Bytes&, …)`
// path goes through `push_back` / `append` on a `std::basic_string<uint8_t>`,
// costing ~5–6 RISC-V instructions per byte through libstdc++'s size /
// capacity bookkeeping. These helpers write through a plain `uint8_t*`
// after the buffer has been resize()d to the exact total length: same
// logic, ~3–4× fewer instructions per byte emitted.
//
// rlp_buffer_ is reserved to 1024 bytes in the ctor so resize() never
// reallocates — that was a real correctness hazard in a prior attempt:
// if `child_ref` (a ByteView passed in from the caller) aliased
// rlp_buffer_'s backing store, a reallocating resize() would invalidate
// the source pointer before the memcpy.

[[gnu::always_inline]] static inline uint8_t* hb_rlp_write_list_header(
    uint8_t* p, size_t payload_length) noexcept {
    if (payload_length < 56) {
        *p++ = static_cast<uint8_t>(rlp::kEmptyListCode + payload_length);
    } else {
        const ByteView len_be = endian::to_big_compact(payload_length);
        *p++ = static_cast<uint8_t>(0xF7 + len_be.size());
        std::memcpy(p, len_be.data(), len_be.size());
        p += len_be.size();
    }
    return p;
}

[[gnu::always_inline]] static inline uint8_t* hb_rlp_write_byteview(
    uint8_t* p, ByteView s) noexcept {
    if (s.size() == 1 && s[0] < rlp::kEmptyStringCode) {
        *p++ = s[0];
        return p;
    }
    if (s.size() < 56) {
        *p++ = static_cast<uint8_t>(rlp::kEmptyStringCode + s.size());
    } else {
        const ByteView len_be = endian::to_big_compact(s.size());
        *p++ = static_cast<uint8_t>(0xB7 + len_be.size());
        std::memcpy(p, len_be.data(), len_be.size());
        p += len_be.size();
    }
    std::memcpy(p, s.data(), s.size());
    p += s.size();
    return p;
}

ByteView HashBuilder::leaf_node_rlp(ByteView path, ByteView value) {
    uint8_t hpbuf[33];
    const size_t hp_size = encode_path(hpbuf, path, /*terminating=*/true);
    const ByteView ep_view{hpbuf, hp_size};
    const size_t payload_length = rlp::length(ep_view) + rlp::length(value);
    const size_t header_size = rlp::length_of_length(payload_length);
    const size_t total_size  = header_size + payload_length;

    rlp_buffer_.resize(total_size);
    auto* p = reinterpret_cast<uint8_t*>(rlp_buffer_.data());
    p = hb_rlp_write_list_header(p, payload_length);
    p = hb_rlp_write_byteview(p, ep_view);
    p = hb_rlp_write_byteview(p, value);
    SILKWORM_ASSERT(static_cast<size_t>(p - reinterpret_cast<uint8_t*>(rlp_buffer_.data())) == total_size);
    return rlp_buffer_;
}

ByteView HashBuilder::extension_node_rlp(ByteView path, ByteView child_ref) {
    uint8_t hpbuf[33];
    const size_t hp_size = encode_path(hpbuf, path, /*terminating=*/false);
    const ByteView ep_view{hpbuf, hp_size};
    const size_t payload_length = rlp::length(ep_view) + child_ref.size();
    const size_t header_size = rlp::length_of_length(payload_length);
    const size_t total_size  = header_size + payload_length;

    rlp_buffer_.resize(total_size);
    auto* p = reinterpret_cast<uint8_t*>(rlp_buffer_.data());
    p = hb_rlp_write_list_header(p, payload_length);
    p = hb_rlp_write_byteview(p, ep_view);
    std::memcpy(p, child_ref.data(), child_ref.size());
    p += child_ref.size();
    SILKWORM_ASSERT(static_cast<size_t>(p - reinterpret_cast<uint8_t*>(rlp_buffer_.data())) == total_size);
    return rlp_buffer_;
}

static Bytes wrap_hash(std::span<const uint8_t, kHashLength> hash) {
    Bytes wrapped(kHashLength + 1, '\0');
    wrapped[0] = rlp::kEmptyStringCode + kHashLength;
    std::memcpy(&wrapped[1], &hash[0], kHashLength);
    return wrapped;
}

static Bytes node_ref(ByteView rlp) {
    if (rlp.size() < kHashLength) {
        return Bytes{rlp};
    }
    const ethash::hash256 hash{keccak256(rlp)};
    return wrap_hash(hash.bytes);
}

void HashBuilder::add_leaf(Bytes key, ByteView value) {
    // SILKWORM_ASSERT(key > key_);
    if (!key_.empty()) {
        gen_struct_step(key_, key);
    }
    key_ = std::move(key);
    value_ = Bytes{value};
}

void HashBuilder::add_branch_node(Bytes nibbled_key, const evmc::bytes32& hash, bool is_in_db_trie) {
    // SILKWORM_ASSERT(nibbled_key > key_ || (key_.empty() && nibbled_key.empty()));
    if (!key_.empty()) {
        gen_struct_step(key_, nibbled_key);
    } else if (nibbled_key.empty()) {
        // known root hash
        stack_.push_back(wrap_hash(hash.bytes));
    }
    key_ = std::move(nibbled_key);
    value_ = hash;
    is_in_db_trie_ = is_in_db_trie;
}

void HashBuilder::finalize() {
    if (!key_.empty()) {
        gen_struct_step(key_, {});
        key_.clear();
        value_ = Bytes{};
    }
}

evmc::bytes32 HashBuilder::root_hash() { return root_hash(/*auto_finalize=*/true); }

evmc::bytes32 HashBuilder::root_hash(bool auto_finalize) {
    if (auto_finalize) {
        finalize();
    }

    if (stack_.empty()) {
        return kEmptyRoot;
    }

    const Bytes& node_ref{stack_.back()};
    evmc::bytes32 res{};
    if (node_ref.size() == kHashLength + 1) {
        std::memcpy(res.bytes, &node_ref[1], kHashLength);
    } else {
        res = std::bit_cast<evmc_bytes32>(keccak256(node_ref));
    }
    return res;
}

// https://github.com/erigontech/erigon/blob/main/docs/programmers_guide/guide.md#generating-the-structural-information-from-the-sequence-of-keys
void HashBuilder::gen_struct_step(ByteView current, const ByteView succeeding) {
    for (bool build_extensions{false};; build_extensions = true) {
        const bool preceding_exists{!groups_.empty()};

        // Calculate the prefix of the smallest prefix group containing current
        const size_t preceding_len{groups_.empty() ? 0 : groups_.size() - 1};
        const size_t common_prefix_len{prefix_length(succeeding, current)};
        const size_t len{std::max(preceding_len, common_prefix_len)};
        // SILKWORM_ASSERT(len < current.size());

        // Add the digit immediately following the max common prefix
        const uint8_t extra_digit{current[len]};
        if (groups_.size() <= len) {
            groups_.resize(len + 1);
        }
        groups_[len] |= 1u << extra_digit;

        if (tree_masks_.size() < current.size()) {
            tree_masks_.resize(current.size());
            hash_masks_.resize(current.size());
        }

        size_t from{len};
        if (!succeeding.empty() || preceding_exists) {
            ++from;
        }

        const ByteView short_node_key{current.substr(from)};
        if (!build_extensions) {
            if (const Bytes* leaf_value{std::get_if<Bytes>(&value_)}) {
                stack_.push_back(node_ref(leaf_node_rlp(short_node_key, *leaf_value)));
            } else {
                stack_.push_back(wrap_hash(std::get<evmc::bytes32>(value_).bytes));
                if (node_collector) {
                    if (is_in_db_trie_) {
                        // keep track of existing records in DB
                        tree_masks_[current.size() - 1] |= 1u << current.back();
                    }
                    // register myself in parent's bitmaps
                    hash_masks_[current.size() - 1] |= 1u << current.back();
                }
                build_extensions = true;
            }
        }

        if (build_extensions && !short_node_key.empty()) {  // extension node
            if (node_collector && from > 0) {
                // See node/silkworm/trie/intermediate_hashes.hpp
                const auto flag{static_cast<uint16_t>(1u << current[from - 1])};

                // DB trie can't use hash of an extension node
                hash_masks_[from - 1] &= ~flag;

                if (tree_masks_[current.size() - 1]) {
                    // Propagate tree_masks flag along the extension node
                    tree_masks_[from - 1] |= flag;
                }
            }

            stack_.back() = node_ref(extension_node_rlp(short_node_key, stack_.back()));

            hash_masks_.resize(from);
            tree_masks_.resize(from);
        }

        // Check for the optional part
        if (preceding_len <= common_prefix_len && !succeeding.empty()) {
            return;
        }

        // Close the immediately encompassing prefix group, if needed
        if (!succeeding.empty() || preceding_exists) {  // branch node
            std::vector<Bytes> child_hashes{branch_ref(groups_[len], hash_masks_[len])};

            // See node/silkworm/trie/intermediate_hashes.hpp
            if (node_collector) {
                if (len > 0) {
                    hash_masks_[len - 1] |= 1u << current[len - 1];
                }

                const bool store_in_db_trie{tree_masks_[len] || hash_masks_[len]};
                if (store_in_db_trie) {
                    if (len > 0) {
                        tree_masks_[len - 1] |= 1u << current[len - 1];  // register myself in parent bitmap
                    }

                    std::vector<evmc::bytes32> hashes(child_hashes.size());
                    for (size_t i{0}; i < child_hashes.size(); ++i) {
                        // SILKWORM_ASSERT(child_hashes[i].size() == kHashLength + 1);
                        std::memcpy(hashes[i].bytes, &child_hashes[i][1], kHashLength);
                    }
                    Node node{groups_[len], tree_masks_[len], hash_masks_[len], hashes};
                    if (len == 0) {
                        node.set_root_hash(root_hash(/*auto_finalize=*/false));
                    }

                    node_collector(current.substr(0, len), node);
                }
            }
        }

        groups_.resize(len);
        tree_masks_.resize(len);
        hash_masks_.resize(len);

        if (preceding_len == 0) {
            return;
        }

        // Update current key for the build_extensions iteration
        current = current.substr(0, preceding_len);
        while (!groups_.empty() && groups_.back() == 0) {
            groups_.pop_back();
        }
    }
}

// Takes children from the stack and replaces them with branch node ref.
std::vector<Bytes> HashBuilder::branch_ref(uint16_t state_mask, uint16_t hash_mask) {
    // SILKWORM_ASSERT(is_subset(hash_mask, state_mask));
    std::vector<Bytes> child_hashes;
    child_hashes.reserve(static_cast<size_t>(std::popcount(hash_mask)));

    const size_t first_child_idx{stack_.size() - static_cast<size_t>(std::popcount(state_mask))};

    // Length of 1 for the nil value added below
    rlp::Header h{.list = true, .payload_length = 1};

    for (size_t i{first_child_idx}, digit{0}; digit < 16; ++digit) {
        if (state_mask & (1u << digit)) {
            h.payload_length += stack_[i++].size();
        } else {
            h.payload_length += 1;
        }
    }

    rlp_buffer_.clear();
    rlp::encode_header(rlp_buffer_, h);

    for (size_t i{first_child_idx}, digit{0}; digit < 16; ++digit) {
        if (state_mask & (1u << digit)) {
            if (hash_mask & (1u << digit)) {
                child_hashes.push_back(stack_[i]);
            }
            rlp_buffer_.append(stack_[i++]);
        } else {
            rlp_buffer_.push_back(rlp::kEmptyStringCode);
        }
    }

    // branch nodes with values are not supported
    rlp_buffer_.push_back(rlp::kEmptyStringCode);

    stack_.resize(first_child_idx + 1);
    stack_.back() = node_ref(rlp_buffer_);

    return child_hashes;
}

void HashBuilder::reset() {
    key_.clear();
    value_ = Bytes();
    is_in_db_trie_ = false;
    groups_.clear();
    tree_masks_.clear();
    hash_masks_.clear();
    stack_.clear();
    rlp_buffer_.clear();
}

}  // namespace silkworm::trie
