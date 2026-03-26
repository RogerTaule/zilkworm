// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0
#include <format>
#include <zilk_core/core/rlp/decode.hpp>
#include <zilk_core/print.hpp>
#include "flat_store.hpp"

namespace silkworm::mpt {

// Function to populate a FlatNodeStore from the given trie_rlp structure
// Layout is [rlp{32-byte hash, bytes}, rlp{32-byte hash, bytes}, ...]
void FlatNodeStore::populate_from_rlp(ByteView trie_rlp) {
    auto trie_header{rlp::decode_header(trie_rlp)};
    if (!trie_header || !trie_header->list) {
        sys_println("Invalid trie_header in populate_from_rlp");
        return;
    }

    ByteView trie_view = trie_rlp.substr(0, trie_header->payload_length);

    while (!trie_view.empty()) {
        bytes32 node_hash;
        Bytes node_rlp;

        // Decode the 32-byte hash as a fixed-size array
        if (DecodingResult res = rlp::decode(trie_view, std::span<uint8_t, 32>{node_hash.bytes}, rlp::Leftover::kAllow); !res) {
            sys_println("Failed to decode node_hash from trie_view");
            break;
        }
        if (!rlp::decode(trie_view, node_rlp, rlp::Leftover::kAllow)) {
            sys_println("Failed to decode node_rlp from trie_view");
            break;
        }
        insert(node_hash, std::move(node_rlp));
    }
}

}  // namespace silkworm::mpt
