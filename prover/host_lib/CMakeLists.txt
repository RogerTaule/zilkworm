# Host-side FFI for zilkworm's state-transition library.
#
# Builds libz6m_host.a, which exposes a single C ABI entry — z6m_run() —
# mirroring the guest_zisk hello.cpp dispatch. The library is consumed by
# zisk-eth-client's `crates/guest-zilkworm` (Rust FFI), which links it against
# ziskos so the read_input / write_output / hint_* symbols resolve at link
# time.
#
# The target depends only on silkworm_dev (which transitively pulls
# silkworm_core, evmone, intx, blst); the caller is expected to add this
# subdirectory after those are available in the build tree.

add_library(z6m_host STATIC ffi.cpp)
target_include_directories(z6m_host PUBLIC include)
target_link_libraries(z6m_host PUBLIC silkworm_dev)
