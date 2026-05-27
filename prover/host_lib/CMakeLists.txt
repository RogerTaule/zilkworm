# Host-side FFI for zilkworm's state-transition library.
#
# Builds libz6m_host.a, which exposes a single C ABI entry — z6m_run() —
# mirroring the guest_zisk hello.cpp dispatch. Consumed by zisk-eth-client's
# `crates/guest-zilkworm` (Rust FFI).
#
# The real work lives in include/z6m_dispatch.hpp's z6m::run() (shared with
# the guest entry in prover/guest_zisk/hello.cpp). evmone's zkvm crypto
# provider is always installed there, so native validation crypto is
# bit-identical to the guest's path.

# Resolve a zisk checkout for <zkvm_io.h> (declares the ziskos C ABI used by
# z6m_dispatch.hpp). The implementations of read_input / write_output come
# from the Rust ziskos crate that the host binary links — we only need the
# header here for compilation. Mirrors the resolution in
# prover/guest_zisk/CMakeLists.txt (which also needs the staticlib .a).
if(NOT DEFINED ZISK_DIR)
    if(DEFINED ENV{ZISK_DIR})
        set(ZISK_DIR "$ENV{ZISK_DIR}")
    else()
        set(ZISK_DIR "$ENV{HOME}/zisk")
    endif()
endif()
if(NOT EXISTS "${ZISK_DIR}/zkvm-interface/zkvm_io.h")
    message(FATAL_ERROR
        "zkvm_io.h not found at ${ZISK_DIR}/zkvm-interface/zkvm_io.h.\n"
        "Set -DZISK_DIR=/path/to/zisk (or ZISK_DIR env var) to a checkout of "
        "https://github.com/0xPolygonHermez/zisk.git")
endif()

add_library(z6m_host STATIC ffi.cpp)
# PUBLIC so consumers of z6m_host (the Rust FFI crate) also see <zkvm_io.h>
# if they need to declare the same ABI directly.
target_include_directories(z6m_host PUBLIC include "${ZISK_DIR}/zkvm-interface")
target_link_libraries(z6m_host PUBLIC silkworm_dev)
