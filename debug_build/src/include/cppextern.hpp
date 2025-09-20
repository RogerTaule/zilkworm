#pragma once
#include <cstdint>
#include <string>
// #include "stub_gthread_cond.hpp";

#ifdef __cplusplus
extern "C" {
#endif

uint64_t sample_run_wrapped(uint32_t n, std::string jsonStr1);

#ifdef __cplusplus
}
#endif