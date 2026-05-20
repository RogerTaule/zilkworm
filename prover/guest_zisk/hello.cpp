/* hello.cpp — L2.b step 3: Transaction encode/decode roundtrip via zilk_core.
 *
 * Builds a legacy (type-0) Transaction in-memory, RLP-encodes it,
 * decodes it back, and verifies the fields match. This pulls
 * types/transaction.cpp into the link with all its RLP encode/decode
 * logic for the legacy + typed wrappers.
 */
#include "zisk_io.h"
#include <intx/intx.hpp>
#include <zilk_core/core/common/base.hpp>
#include <zilk_core/core/rlp/encode.hpp>
#include <zilk_core/core/rlp/decode.hpp>
#include <zilk_core/core/types/transaction.hpp>

static void print_bytes_hex(silkworm::ByteView bv) {
    for (uint8_t b : bv) {
        uart_putc("0123456789abcdef"[(b >> 4) & 0xf]);
        uart_putc("0123456789abcdef"[b & 0xf]);
    }
    uart_putc('\n');
}

int main() {
    silkworm::Transaction tx;
    tx.type = silkworm::TransactionType::kLegacy;
    tx.nonce = 7;
    tx.max_priority_fee_per_gas = intx::uint256{0x09184e72a000ULL};  /* legacy uses gas_price */
    tx.max_fee_per_gas = intx::uint256{0x09184e72a000ULL};
    tx.gas_limit = 0x2710;
    tx.to = evmc::address{};
    tx.to->bytes[19] = 0x01;  /* recipient 0x...01 */
    tx.value = intx::uint256{0x16345785d8a0000ULL};  /* 0.1 ETH */
    tx.data = {};
    tx.odd_y_parity = false;
    tx.r = intx::uint256{0x1234};
    tx.s = intx::uint256{0x5678};

    silkworm::Bytes encoded;
    silkworm::rlp::encode(encoded, tx);

    sys_println("encoded RLP:");
    print_bytes_hex(silkworm::ByteView{encoded.data(), encoded.size()});
    sys_println("encoded length:");
    sys_print_u64_hex(static_cast<uint64_t>(encoded.size()));
    uart_putc('\n');

    silkworm::Transaction decoded;
    silkworm::ByteView view{encoded.data(), encoded.size()};
    auto res = silkworm::rlp::decode(view, decoded);

    sys_println("decode result (0 = ok):");
    sys_print_u64_hex(res ? 0 : static_cast<uint64_t>(res.error()));
    uart_putc('\n');

    sys_println("decoded.nonce:");
    sys_print_u64_hex(decoded.nonce);
    uart_putc('\n');

    sys_println("decoded.gas_limit:");
    sys_print_u64_hex(decoded.gas_limit);
    uart_putc('\n');

    sys_println("decoded.value (low u64):");
    sys_print_u64_hex(static_cast<uint64_t>(decoded.value));
    uart_putc('\n');

    bool match =
        decoded.nonce == tx.nonce &&
        decoded.gas_limit == tx.gas_limit &&
        decoded.value == tx.value &&
        decoded.to == tx.to;
    sys_println(match ? "MATCH" : "MISMATCH");

    set_output_u64(0, decoded.nonce);
    set_output_u64(8, decoded.gas_limit);
    return 0;
}
