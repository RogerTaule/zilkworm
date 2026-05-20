/* hello.cpp — smoke test for std::vector growth on Zisk.
 *
 * Reads N as a little-endian u64 from input, then builds
 * std::vector<u64> v with N entries (each being i+1). Outputs the
 * sum, which is N*(N+1)/2. This exercises the heap path through
 * repeated push_back reallocations and iteration via range-for, on
 * top of the std::string baseline from the previous commit.
 */
#include "zisk_io.h"
#include <string>
#include <vector>

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
    if (n > 100) n = 100;  /* keep the smoke test bounded */

    std::vector<unsigned long> v;
    for (unsigned long i = 0; i < n; ++i) v.push_back(i + 1);

    unsigned long sum = 0;
    for (unsigned long e : v) sum += e;

    std::string label = "sum 1..N (hex):";
    sys_println(label.c_str());
    sys_print_u64_hex(sum);
    uart_putc('\n');

    set_output_u64(0, sum);
    return 0;
}
