#include "./include/cppextern.hpp"
#include <cstdio>

// Minimal semihosting "puts" to guarantee console prints even without stdio plumbing.
static inline void sh_write0(const char* s) {
    register long a0 asm("a0") = 0x04;      // SYS_WRITE0
    register const char* a1 asm("a1") = s;  // pointer to 0-terminated string
    asm volatile(
        ".option push       \n"
        ".option norvc      \n"  // avoid C extension in the magic sequence
        "slli x0, x0, 0x1f  \n"
        "ebreak             \n"
        "srai x0, x0, 0x7   \n"
        ".option pop        \n"
        : "+r"(a0) : "r"(a1) : "memory"
    );
}

int main() {
    // auto res = sample_run_wrapped();
    // auto res = 1;
    sh_write0("Silkworm RV32 demo starting...\n");
    // printf("State transition result: %d\n", res);
    // printf("State transition result: %d\n", res);
    while (1) {} // loop indefinitely (no OS to return to)
}