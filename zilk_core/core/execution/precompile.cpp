// Copyright 2026 The Zilkworm Authors (modifications)
// Copyright 2025 The Original Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#include "precompile.hpp"

#include <algorithm>
#include <bit>
#include <cstring>
#include <limits>

#include <evmone/crypto_provider.hpp>
#include <zilk_core/core/common/endian.hpp>
#include <zilk_core/core/crypto/ecdsa.h>
#include <zilk_core/core/crypto/secp256k1n.hpp>
#include <zilk_core/core/protocol/intrinsic_gas.hpp>
#include <zilk_core/core/types/hash.hpp>

namespace silkworm::precompile {

static void right_pad(Bytes& str, const size_t min_size) noexcept {
    if (str.size() < min_size) {
        str.resize(min_size, '\0');
    }
}

uint64_t ecrec_gas(ByteView, evmc_revision) noexcept { return 3'000; }

std::optional<Bytes> ecrec_run(ByteView input) noexcept {
    Bytes d{input};
    right_pad(d, 128);

    const auto v{intx::be::unsafe::load<intx::uint256>(&d[32])};
    const auto r{intx::be::unsafe::load<intx::uint256>(&d[64])};
    const auto s{intx::be::unsafe::load<intx::uint256>(&d[96])};

    const bool homestead{false};  // See EIP-2
    if (!is_valid_signature(r, s, homestead)) {
        return Bytes{};
    }

    if (v != 27 && v != 28) {
        return Bytes{};
    }

    Bytes out(32, 0);
    if (!silkworm_recover_address(&out[12], &d[0], &d[64], v != 27)) {
        return Bytes{};
    }
    return out;
}

uint64_t sha256_gas(ByteView input, evmc_revision) noexcept {
    return 60 + 12 * num_words(input.size());
}

std::optional<Bytes> sha256_run(ByteView input) noexcept {
    Bytes out(32, 0);
    evmone::crypto::current_crypto_provider().sha256(out.data(), input.data(), input.size());
    return out;
}

uint64_t rip160_gas(ByteView input, evmc_revision) noexcept {
    return 600 + 120 * num_words(input.size());
}

std::optional<Bytes> rip160_run(ByteView input) noexcept {
    Bytes out(32, 0);
    evmone::crypto::current_crypto_provider().ripemd160(&out[12], input.data(), input.size());
    return out;
}

uint64_t id_gas(ByteView input, evmc_revision) noexcept {
    return 15 + 3 * num_words(input.size());
}

std::optional<Bytes> id_run(ByteView input) noexcept {
    return Bytes{input};
}

static intx::uint256 mult_complexity_eip198(const intx::uint256& x) noexcept {
    const intx::uint256 x_squared{x * x};
    if (x <= 64) {
        return x_squared;
    }
    if (x <= 1024) {
        return (x_squared >> 2) + 96 * x - 3072;
    }
    return (x_squared >> 4) + 480 * x - 199680;
}

static intx::uint256 mult_complexity_eip2565(const intx::uint256& max_length) noexcept {
    const intx::uint256 words{(max_length + 7) >> 3};  // ⌈max_length/8⌉
    return words * words;
}

uint64_t expmod_gas(ByteView input_view, evmc_revision rev) noexcept {
    const uint64_t min_gas{rev < EVMC_BERLIN ? 0 : 200u};

    Bytes input{input_view};
    right_pad(input, 3 * 32);

    intx::uint256 base_len256{intx::be::unsafe::load<intx::uint256>(&input[0])};
    intx::uint256 exp_len256{intx::be::unsafe::load<intx::uint256>(&input[32])};
    intx::uint256 mod_len256{intx::be::unsafe::load<intx::uint256>(&input[64])};

    if (base_len256 == 0 && mod_len256 == 0) {
        return min_gas;
    }

    if (intx::count_significant_words(base_len256) > 1 || intx::count_significant_words(exp_len256) > 1 ||
        intx::count_significant_words(mod_len256) > 1) {
        return UINT64_MAX;
    }

    uint64_t base_len64{static_cast<uint64_t>(base_len256)};
    uint64_t exp_len64{static_cast<uint64_t>(exp_len256)};

    input.erase(0, 3 * 32);

    intx::uint256 exp_head{0};  // first 32 bytes of the exponent
    if (input.size() > base_len64) {
        input.erase(0, static_cast<size_t>(base_len64));
        right_pad(input, 3 * 32);
        if (exp_len64 < 32) {
            input.erase(static_cast<size_t>(exp_len64));
            input.insert(0, 32 - static_cast<size_t>(exp_len64), '\0');
        }
        exp_head = intx::be::unsafe::load<intx::uint256>(input.data());
    }
    unsigned bit_len{256 - clz(exp_head)};

    intx::uint256 adjusted_exponent_len{0};
    if (exp_len256 > 32) {
        adjusted_exponent_len = 8 * (exp_len256 - 32);
    }
    if (bit_len > 1) {
        adjusted_exponent_len += bit_len - 1;
    }

    if (adjusted_exponent_len < 1) {
        adjusted_exponent_len = 1;
    }

    const intx::uint256 max_length{std::max(mod_len256, base_len256)};

    intx::uint256 gas;
    if (rev < EVMC_BERLIN) {
        gas = mult_complexity_eip198(max_length) * adjusted_exponent_len / 20;
    } else {
        gas = mult_complexity_eip2565(max_length) * adjusted_exponent_len / 3;
    }

    if (intx::count_significant_words(gas) > 1) {
        return UINT64_MAX;
    }
    return std::max(min_gas, static_cast<uint64_t>(gas));
}

std::optional<Bytes> expmod_run(ByteView input_view) noexcept {
    Bytes input{input_view};
    right_pad(input, 3 * 32);

    const auto base_len = static_cast<size_t>(intx::be::unsafe::load<intx::uint256>(&input[0]));
    const auto exp_len = static_cast<size_t>(intx::be::unsafe::load<intx::uint256>(&input[32]));
    const auto mod_len = static_cast<size_t>(intx::be::unsafe::load<intx::uint256>(&input[64]));

    Bytes out(mod_len, 0);
    if (mod_len == 0) {
        return out;
    }

    right_pad(input, 3 * 32 + base_len + exp_len + mod_len);

    const std::span<const uint8_t> mod{&input[96 + base_len + exp_len], mod_len};
    if (std::ranges::all_of(mod, [](uint8_t b) { return b == 0; })) {
        // Modulus is zero → result is zero. Avoids divide-by-zero in the bigint backend.
        return out;
    }

    const std::span<const uint8_t> base{&input[96], base_len};
    const std::span<const uint8_t> exp{&input[96 + base_len], exp_len};
    evmone::crypto::current_crypto_provider().modexp(base, exp, mod, out.data());
    return out;
}

uint64_t bn_add_gas(ByteView, evmc_revision rev) noexcept {
    return rev >= EVMC_ISTANBUL ? 150 : 500;
}

std::optional<Bytes> bn_add_run(ByteView input) noexcept {
    uint8_t buf[128]{};
    if (!input.empty()) {
        std::memcpy(buf, input.data(), std::min(input.size(), sizeof(buf)));
    }
    Bytes out(64, 0);
    if (!evmone::crypto::current_crypto_provider().bn254_g1_add(out.data(), buf, buf + 64)) {
        return std::nullopt;
    }
    return out;
}

uint64_t bn_mul_gas(ByteView, evmc_revision rev) noexcept {
    return rev >= EVMC_ISTANBUL ? 6'000 : 40'000;
}

std::optional<Bytes> bn_mul_run(ByteView input) noexcept {
    uint8_t buf[96]{};
    if (!input.empty()) {
        std::memcpy(buf, input.data(), std::min(input.size(), sizeof(buf)));
    }
    Bytes out(64, 0);
    if (!evmone::crypto::current_crypto_provider().bn254_g1_mul(out.data(), buf, buf + 64)) {
        return std::nullopt;
    }
    return out;
}

uint64_t snarkv_gas(ByteView input, evmc_revision rev) noexcept {
    const uint64_t base{rev >= EVMC_ISTANBUL ? 45'000u : 100'000u};
    const uint64_t per_pair{rev >= EVMC_ISTANBUL ? 34'000u : 80'000u};
    return base + per_pair * (input.size() / 192);
}

std::optional<Bytes> snarkv_run(ByteView input) noexcept {
    constexpr size_t kPairSize = 192;
    if (input.size() % kPairSize != 0) {
        return std::nullopt;
    }
    bool verified{false};
    if (!evmone::crypto::current_crypto_provider().bn254_pairing(
            verified, input.data(), input.size() / kPairSize)) {
        return std::nullopt;
    }
    Bytes out(32, 0);
    out[31] = verified ? 1 : 0;
    return out;
}

uint64_t blake2_f_gas(ByteView input, evmc_revision) noexcept {
    if (input.size() < 4) {
        // blake2_f_run will fail anyway
        return 0;
    }
    return endian::load_big_u32(input.data());
}

std::optional<Bytes> blake2_f_run(ByteView input) noexcept {
    if (input.size() != 213) {
        return std::nullopt;
    }
    const uint8_t f{input[212]};
    if (f != 0 && f != 1) {
        return std::nullopt;
    }

    uint64_t h[8];
    std::memcpy(h, &input[4], sizeof(h));
    uint64_t m[16];
    std::memcpy(m, &input[68], sizeof(m));
    uint64_t t[2];
    std::memcpy(t, &input[196], sizeof(t));

    static_assert(std::endian::native == std::endian::little);

    const uint32_t r{endian::load_big_u32(input.data())};
    evmone::crypto::current_crypto_provider().blake2f(r, h, m, t, f);

    Bytes out(sizeof(h), 0);
    std::memcpy(&out[0], h, sizeof(h));
    return out;
}

uint64_t point_evaluation_gas(ByteView, evmc_revision) noexcept {
    return 50000;
}

// https://eips.ethereum.org/EIPS/eip-4844#point-evaluation-precompile
std::optional<Bytes> point_evaluation_run(ByteView input) noexcept {
    if (input.size() != 192) {
        return std::nullopt;
    }

    bool verified = false;
    if (!evmone::crypto::current_crypto_provider().kzg_point_eval(
            verified, /*vh=*/&input[0], /*commitment=*/&input[96], /*z=*/&input[32],
            /*y=*/&input[64], /*proof=*/&input[144])) {
        return std::nullopt;
    }
    if (!verified) {
        return std::nullopt;
    }

    return from_hex(
        "0000000000000000000000000000000000000000000000000000000000001000"
        "73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");
}

// -- EIP-2537: BLS12-381 ------------------------------------------------------
//
// All gas tables, layouts and discount arrays match evmone's
// test/state/precompiles.cpp BLS12 analyzers. Inputs use EVM byte format
// (each Fp is 64 bytes with a 16-byte zero prefix); the provider takes the
// same EVM format and absorbs any compact/expanded conversion internally.

namespace {

constexpr size_t kBls12FieldElementSize = 64;
constexpr size_t kBls12G1PointSize = 2 * kBls12FieldElementSize;                   // 128
constexpr size_t kBls12G2PointSize = 4 * kBls12FieldElementSize;                   // 256
constexpr size_t kBls12ScalarSize = 32;
constexpr size_t kBls12G1MulInputSize = kBls12G1PointSize + kBls12ScalarSize;      // 160
constexpr size_t kBls12G2MulInputSize = kBls12G2PointSize + kBls12ScalarSize;      // 288
constexpr size_t kBls12PairingPairSize = kBls12G1PointSize + kBls12G2PointSize;    // 384

constexpr uint16_t kBls12G1MsmDiscounts[128] = {
    1000, 949, 848, 797, 764, 750, 738, 728, 719, 712, 705, 698, 692, 687, 682, 677,
    673, 669, 665, 661, 658, 654, 651, 648, 645, 642, 640, 637, 635, 632, 630, 627,
    625, 623, 621, 619, 617, 615, 613, 611, 609, 608, 606, 604, 603, 601, 599, 598,
    596, 595, 593, 592, 591, 589, 588, 586, 585, 584, 582, 581, 580, 579, 577, 576,
    575, 574, 573, 572, 570, 569, 568, 567, 566, 565, 564, 563, 562, 561, 560, 559,
    558, 557, 556, 555, 554, 553, 552, 551, 550, 549, 548, 547, 547, 546, 545, 544,
    543, 542, 541, 540, 540, 539, 538, 537, 536, 536, 535, 534, 533, 532, 532, 531,
    530, 529, 528, 528, 527, 526, 525, 525, 524, 523, 522, 522, 521, 520, 520, 519};

constexpr uint16_t kBls12G2MsmDiscounts[128] = {
    1000, 1000, 923, 884, 855, 832, 812, 796, 782, 770, 759, 749, 740, 732, 724, 717,
    711, 704, 699, 693, 688, 683, 679, 674, 670, 666, 663, 659, 655, 652, 649, 646,
    643, 640, 637, 634, 632, 629, 627, 624, 622, 620, 618, 615, 613, 611, 609, 607,
    606, 604, 602, 600, 598, 597, 595, 593, 592, 590, 589, 587, 586, 584, 583, 582,
    580, 579, 578, 576, 575, 574, 573, 571, 570, 569, 568, 567, 566, 565, 563, 562,
    561, 560, 559, 558, 557, 556, 555, 554, 553, 552, 552, 551, 550, 549, 548, 547,
    546, 545, 545, 544, 543, 542, 541, 541, 540, 539, 538, 537, 537, 536, 535, 535,
    534, 533, 532, 532, 531, 530, 530, 529, 528, 528, 527, 526, 526, 525, 524, 524};

}  // namespace

uint64_t bls12_g1_add_gas(ByteView, evmc_revision) noexcept {
    return 375;
}

std::optional<Bytes> bls12_g1_add_run(ByteView input) noexcept {
    if (input.size() != 2 * kBls12G1PointSize) {
        return std::nullopt;
    }
    Bytes out(kBls12G1PointSize, 0);
    if (!evmone::crypto::current_crypto_provider().bls12_g1_add(
            out.data(), input.data(), &input[kBls12G1PointSize])) {
        return std::nullopt;
    }
    return out;
}

uint64_t bls12_g1_msm_gas(ByteView input, evmc_revision) noexcept {
    if (input.empty() || input.size() % kBls12G1MulInputSize != 0) {
        return UINT64_MAX;
    }
    const size_t k = input.size() / kBls12G1MulInputSize;
    const auto discount = kBls12G1MsmDiscounts[std::min(k, std::size(kBls12G1MsmDiscounts)) - 1];
    return (12'000ull * discount * k) / 1000;
}

std::optional<Bytes> bls12_g1_msm_run(ByteView input) noexcept {
    if (input.empty() || input.size() % kBls12G1MulInputSize != 0) {
        return std::nullopt;
    }
    Bytes out(kBls12G1PointSize, 0);
    if (!evmone::crypto::current_crypto_provider().bls12_g1_msm(
            out.data(), input.data(), input.size() / kBls12G1MulInputSize)) {
        return std::nullopt;
    }
    return out;
}

uint64_t bls12_g2_add_gas(ByteView, evmc_revision) noexcept {
    return 600;
}

std::optional<Bytes> bls12_g2_add_run(ByteView input) noexcept {
    if (input.size() != 2 * kBls12G2PointSize) {
        return std::nullopt;
    }
    Bytes out(kBls12G2PointSize, 0);
    if (!evmone::crypto::current_crypto_provider().bls12_g2_add(
            out.data(), input.data(), &input[kBls12G2PointSize])) {
        return std::nullopt;
    }
    return out;
}

uint64_t bls12_g2_msm_gas(ByteView input, evmc_revision) noexcept {
    if (input.empty() || input.size() % kBls12G2MulInputSize != 0) {
        return UINT64_MAX;
    }
    const size_t k = input.size() / kBls12G2MulInputSize;
    const auto discount = kBls12G2MsmDiscounts[std::min(k, std::size(kBls12G2MsmDiscounts)) - 1];
    return (22'500ull * discount * k) / 1000;
}

std::optional<Bytes> bls12_g2_msm_run(ByteView input) noexcept {
    if (input.empty() || input.size() % kBls12G2MulInputSize != 0) {
        return std::nullopt;
    }
    Bytes out(kBls12G2PointSize, 0);
    if (!evmone::crypto::current_crypto_provider().bls12_g2_msm(
            out.data(), input.data(), input.size() / kBls12G2MulInputSize)) {
        return std::nullopt;
    }
    return out;
}

uint64_t bls12_pairing_gas(ByteView input, evmc_revision) noexcept {
    if (input.empty() || input.size() % kBls12PairingPairSize != 0) {
        return UINT64_MAX;
    }
    const size_t npairs = input.size() / kBls12PairingPairSize;
    return 37'700 + 32'600ull * npairs;
}

std::optional<Bytes> bls12_pairing_run(ByteView input) noexcept {
    if (input.empty() || input.size() % kBls12PairingPairSize != 0) {
        return std::nullopt;
    }
    bool verified{false};
    if (!evmone::crypto::current_crypto_provider().bls12_pairing(
            verified, input.data(), input.size() / kBls12PairingPairSize)) {
        return std::nullopt;
    }
    Bytes out(32, 0);
    out[31] = verified ? 1 : 0;
    return out;
}

uint64_t bls12_map_fp_to_g1_gas(ByteView, evmc_revision) noexcept {
    return 5500;
}

std::optional<Bytes> bls12_map_fp_to_g1_run(ByteView input) noexcept {
    if (input.size() != kBls12FieldElementSize) {
        return std::nullopt;
    }
    Bytes out(kBls12G1PointSize, 0);
    if (!evmone::crypto::current_crypto_provider().bls12_map_fp_to_g1(out.data(), input.data())) {
        return std::nullopt;
    }
    return out;
}

uint64_t bls12_map_fp2_to_g2_gas(ByteView, evmc_revision) noexcept {
    return 23'800;
}

std::optional<Bytes> bls12_map_fp2_to_g2_run(ByteView input) noexcept {
    if (input.size() != 2 * kBls12FieldElementSize) {
        return std::nullopt;
    }
    Bytes out(kBls12G2PointSize, 0);
    if (!evmone::crypto::current_crypto_provider().bls12_map_fp2_to_g2(out.data(), input.data())) {
        return std::nullopt;
    }
    return out;
}

bool is_precompile(const evmc::address& address, evmc_revision rev) noexcept {
    using namespace evmc::literals;

    static_assert(std::size(kContracts) < 256);
    static constexpr evmc::address kMaxOneByteAddress{0x00000000000000000000000000000000000000ff_address};
    if (address > kMaxOneByteAddress) {
        return false;
    }

    const uint8_t num{address.bytes[kAddressLength - 1]};
    if (num >= std::size(kContracts) || !kContracts[num]) {
        return false;
    }

    return kContracts[num]->added_in <= rev;
}

}  // namespace silkworm::precompile
