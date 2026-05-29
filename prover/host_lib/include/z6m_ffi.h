/* Copyright 2026 The Zilkworm Authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Host-side FFI for zilkworm's C++ state-transition library.
 *
 * Provides a single entry point — z6m_run() — that mirrors the guest_zisk
 * hello.cpp main, but compiled for native (host) targets. It drives execution
 * end-to-end through ziskos's C ABI:
 *
 *   - reads input via read_input (declared in zkvm-interface/zkvm_io.h, impl
 *     in ziskos's zkvm_io.rs);
 *   - runs StateTransition (which emits hint_* during EVM execution — those
 *     resolve to ziskos's native hint impl when linked into a host binary);
 *   - writes gas_used via write_output.
 *
 * Linkage: callers must link this library against ziskos so the read_input /
 * write_output / hint_* extern "C" symbols resolve at link time.
 */
#ifndef ZILKWORM_PROVER_HOST_LIB_Z6M_FFI_H_
#define ZILKWORM_PROVER_HOST_LIB_Z6M_FFI_H_

#ifdef __cplusplus
extern "C" {
#endif

/* Self-contained native run: drives ziskos input/output internally and
 * dispatches on the input's leading is_test byte. Returns when the run
 * finishes (gas_used has been committed via write_output). */
void z6m_run(void);

#ifdef __cplusplus
}
#endif

#endif
