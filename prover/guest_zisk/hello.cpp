/* hello.cpp — L1 smoke test: call into zilk_core's common/ static lib.
 *
 * Builds on L0 by linking the freshly-cross-compiled zilk_core_common
 * static library. silkworm::endian::to_big_compact() encodes a u64 as
 * a big-endian byte string with leading zeros stripped. The call pulls
 * endian.cpp.o (the function itself) and util.cpp.o (zeroless_view) into
 * the executable.
 *
 * For N=0x1234:        output bytes "12 34"
 * For N=0xDEADBEEF:    output bytes "DE AD BE EF"
 * For N=0:             empty
 */
#include "zisk_io.h"
#include <intx/intx.hpp>
#include <zilk_core/core/common/endian.hpp>

static unsigned long read_u64_le(const unsigned char *p) {
    unsigned long v = 0;
    for (int i = 0; i < 8; ++i) v |= ((unsigned long)p[i]) << (8 * i);
    return v;
}

int main() {
    zisk_input_t inp = read_input();
    if (inp.len < 8) {
        sys_println("ERROR: need >=8 bytes of input");
        return 1;
    }
    unsigned long n = read_u64_le(inp.ptr);

    silkworm::ByteView v = silkworm::endian::to_big_compact(n);

    sys_println("to_big_compact(N), bytes (hex, big-endian, zeroless):");
    sys_print_u64_hex(static_cast<uint64_t>(v.size()));
    uart_putc(' ');
    for (auto b : v) {
        uart_putc("0123456789abcdef"[(b >> 4) & 0xf]);
        uart_putc("0123456789abcdef"[b & 0xf]);
    }
    uart_putc('\n');

    /* set_output: byte 0 = length, bytes 1..len = payload (little-endian
       packing into u64s isn't strictly necessary — we just stash the bytes
       so a host could read them back). */
    set_output_u32(0, static_cast<uint32_t>(v.size()));
    for (uint32_t i = 0; i < v.size(); ++i) {
        /* one byte per u32 slot; wasteful but simple to verify */
        set_output_u32(4 + i * 4, v[i]);
    }
    return 0;
}
