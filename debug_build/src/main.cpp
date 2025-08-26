#include "./include/cppextern.hpp"
#include <cstdio>

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
    const uint64_t res = sample_run_wrapped();
    char buf[64];
    std::snprintf(buf, sizeof(buf), "State transition result: %llu", (unsigned long long)res);
    sh_write0(buf);
    // printf("State transition result: %d\n", res);
    while (1) {} // loop indefinitely (no OS to return to)
    // return 0;   // Don't
}