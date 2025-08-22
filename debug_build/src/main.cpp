#include "./include/cppextern.hpp"
#include <cstdio>

// Minimal semihosting "puts" to guarantee console prints even without stdio plumbing.

int main() {
    auto res = sample_run_wrapped();
    // auto res = 1;

    // printf("State transition result: %d\n", res);
    // printf("State transition result: %d\n", res);
    while (1) {} // loop indefinitely (no OS to return to)
}