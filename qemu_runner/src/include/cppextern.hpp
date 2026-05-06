// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0

#pragma once
#include <cstdint>
#include <string>
// #include "stub_gthread_cond.hpp";

#ifdef __cplusplus
extern "C" {
#endif

uint64_t sample_run_wrapped(bool is_test, std::string jsonStr1);

#ifdef __cplusplus
}
#endif