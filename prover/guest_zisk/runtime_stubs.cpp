/* runtime_stubs.cpp — stubs for libc symbols referenced by the C++
 * stdlib (or libc) that don't make sense in a deterministic zkVM context.
 *
 * Linked in to satisfy the linker; SHOULD NEVER BE CALLED at runtime.
 * If called, we halt the program loudly (non-determinism breaks proofs).
 */

#include <stddef.h>

extern "C" int _getentropy(void *buf, size_t len) {
    (void)buf; (void)len;
    /* Non-determinism is forbidden in proof generation. Halt loudly. */
    const char msg[] = "FATAL: _getentropy called -- non-determinism forbidden\n";
    volatile unsigned char *uart = (volatile unsigned char *)0xA0000200;
    for (const char *p = msg; *p; ++p) *uart = (unsigned char)*p;
    *(volatile unsigned int *)0x100000 = 0x5555;
    for (;;) {}
    return -1;
}
