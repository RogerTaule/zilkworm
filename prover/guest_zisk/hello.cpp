/* hello.cpp — Zisk guest entry for block execution.
 *
 * All real logic lives in prover/host_lib/include/z6m_dispatch.hpp's
 * `z6m::run()`, which is also wrapped by prover/host_lib/ffi.cpp's
 * `z6m_run()` extern-C entry for the host FFI.
 *
 * z6m::run() calls `extern "C" read_input` and `extern "C" write_output`.
 * Both targets resolve those symbols from ziskos's static library (Rust
 * `ziskos` crate, built per-target). Same C ABI, same semantics — including
 * the `fcall_input_ready` soundness signal the guest impl emits.
 *
 * The guest builds with -fno-exceptions, so any throw inside z6m::run aborts;
 * the host's ffi.cpp wraps in try/catch and surfaces a u64 failure sentinel.
 */

#include "z6m_dispatch.hpp"

int main() {
    z6m::run();
    return 0;
}
