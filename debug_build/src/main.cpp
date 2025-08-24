#include "./include/cppextern.hpp"
#include <cstdio>

int main() {
    auto res = sample_run_wrapped();
    // printf("State transition result: %d\n", res);
    while (1) {} // loop indefinitely (no OS to return to)
    // return 0;   // Don't
}