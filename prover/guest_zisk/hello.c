#include "zisk_io.h"

static unsigned long read_u64_le(const unsigned char *p) {
    unsigned long v = 0;
    for (int i = 0; i < 8; ++i) v |= ((unsigned long)p[i]) << (8 * i);
    return v;
}

int main(void) {
    zisk_input_t inp = read_input();
    if (inp.len < 8) {
        sys_println("ERROR: need >=8 bytes of input");
        return 1;
    }
    unsigned long x = read_u64_le(inp.ptr);
    unsigned long y = x * 2;

    sys_println("input * 2 (hex):");
    sys_print_u64_hex(y);
    uart_putc('\n');

    set_output_u64(0, y);
    return 0;
}
