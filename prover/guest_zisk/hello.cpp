/* hello.cpp — smoke test for intx::uint256 under Zisk (L0 milestone).
 *
 * Reads N as a little-endian u64 from input, then computes
 *   c = uint256(N) * uint256(0xFFFF_FFFF_FFFF_FFFF)
 * and prints the low two 64-bit words of c. The multiplication
 * deliberately produces a value larger than u64 (N * (2^64 - 1) needs
 * two words for any N > 1), so it exercises intx's multi-word math.
 *
 * For N=5: c = 5 * (2^64 - 1) = 5*2^64 - 5
 *          w0 = 0xFFFFFFFFFFFFFFFB
 *          w1 = 0x0000000000000004
 *
 * Validates: g++ accepts C++23 for this target and intx headers
 * compile cross-compiled.
 */
#include "zisk_io.h"
#include <intx/intx.hpp>

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

    intx::uint256 a{0xFFFFFFFFFFFFFFFFULL};
    intx::uint256 b{n};
    intx::uint256 c = a * b;

    /* Extract the low two 64-bit words. */
    auto w0 = static_cast<uint64_t>(c);
    auto w1 = static_cast<uint64_t>(c >> 64);

    sys_println("uint256 N * (2^64 - 1), low 2 words (hex):");
    sys_print_u64_hex(w1);
    uart_putc(' ');
    sys_print_u64_hex(w0);
    uart_putc('\n');

    set_output_u64(0, w0);
    set_output_u64(8, w1);
    return 0;
}
