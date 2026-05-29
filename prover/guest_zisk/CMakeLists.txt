# Zisk guest entry — C++ program built into the z6m_guest.elf RISC-V binary
# that runs under the Zisk zkVM. Dispatches to z6m::run() in
# prover/host_lib/include/z6m_dispatch.hpp (shared with the host FFI).
#
# Configure with the toolchain file:
#   cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE=cmake/zisk-toolchain.cmake
#   cmake --build build
# Output: build/z6m_guest.elf — run with `ziskemu -e build/z6m_guest.elf -i <input.bin>`.
#
# Requires a sibling zisk checkout for zkvm_io.h + libziskos_staticlib.a; see
# the ZISK_DIR block below for resolution and the one-shot build command.

cmake_minimum_required(VERSION 3.28)

set(Z6M_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)

# Bootstrap Cable (the cmake helper bundled with evmone) before project() —
# the same pattern guest_hypercube uses. It provides CableBuildType /
# CableBuildInfo macros and is required by the evmone + blst plumbing in
# third_party/CMakeLists.txt.
include(${Z6M_ROOT}/third_party/evmone/cmake/cable/bootstrap.cmake)
include(CableBuildType)
cable_set_build_type(DEFAULT Release CONFIGURATION_TYPES Release)

project(zisk_guest_poc LANGUAGES C CXX ASM)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Variable expected by third_party/ and zilk_core/ build glue.
set(SILKWORM_MAIN_DIR ${Z6M_ROOT})

# Define ZISK globally before adding zilk_core/third_party so any
# #ifdef ZISK gating (e.g. zilk_core/print.hpp's UART branch) picks
# the bare-metal path instead of std::cout.
add_compile_definitions(ZISK)
# Also expose ZISK as a CMake variable so third_party glue (notably
# evmone/cmake/blst.cmake) can pick the ZISK-specific blst patch.
set(ZISK TRUE)

include(CableBuildInfo)
cable_add_buildinfo_library(PROJECT_NAME zilkworm GIT_DESCRIBE "" GIT_BRANCH "")

# Pull in the real third_party targets (intx::intx, evmc, evmone,
# blst::blst) and zilk_core (which defines silkworm_core).
add_subdirectory(${Z6M_ROOT}/third_party ${CMAKE_BINARY_DIR}/third_party)
add_subdirectory(${Z6M_ROOT}/zilk_core   ${CMAKE_BINARY_DIR}/zilk_core)

add_executable(z6m_guest.elf
    hello.cpp
    arena_malloc.cpp
    runtime_stubs.cpp
    # Custom entry: like ziskos's _start, but also iterates .init_array to
    # run C++ static constructors before calling main(). evmone has heavy
    # static-init (crypto provider tables, precompile dispatch) that segv'd
    # at runtime when we used ziskos's _start, which skips ctors.
    _start.s
    # Local memcpy/memset/memcmp/memmove via Zisk DMA syscalls (sourced
    # from ziskos/entrypoint/src/dma/*.s). libziskos_staticlib.a also has
    # these, BUT they sit in the same .o as ziskos's _start — linking them
    # from the staticlib would drag _start in and collide with our entry
    # above. Keeping local copies of these tiny files means ld never needs
    # that .o, so the staticlib only contributes I/O + zkvm_* symbols.
    memmove.cpp
    dma/memcpy.s
    dma/memset.s
    dma/memcmp.s
    # Override libgcc's software multiply/divide/clz/ctz/popcount helpers
    # with versions that lower to native rv64IM instructions. The xPack
    # toolchain picks the rv64ia libgcc multilib for our -march and thus
    # ships software shift-and-add helpers; this file shadows them.
    libgcc_overrides.cpp
    # Zisk syscall override for evmone's portable sha256 (the `crypto::sha256`
    # function, gated by `#elif defined(ZISK)`). With the zkvm crypto provider
    # installed, every precompile and silkworm-side sha256 routes through the
    # provider (→ zkvm_sha256), not crypto::sha256 — so this override only
    # fires if the default provider is ever active. Cheap insurance; keep it.
    precompiles/zisk_sha256.cpp
)

# Resolve a zisk checkout (provides zkvm_io.h + ziskos-staticlib). Honor
# -DZISK_DIR=... first, then $ENV{ZISK_DIR}, then a sensible local default.
if(NOT DEFINED ZISK_DIR)
    if(DEFINED ENV{ZISK_DIR})
        set(ZISK_DIR "$ENV{ZISK_DIR}")
    else()
        set(ZISK_DIR "$ENV{HOME}/zisk")
    endif()
endif()
set(_ziskos_staticlib
    "${ZISK_DIR}/target/riscv64ima-zisk-zkvm-elf/release/libziskos_staticlib.a")
set(_zkvm_interface_inc "${ZISK_DIR}/zkvm-interface")

if(NOT EXISTS "${_zkvm_interface_inc}/zkvm_io.h")
    message(FATAL_ERROR
        "zkvm_io.h not found at ${_zkvm_interface_inc}/zkvm_io.h.\n"
        "Set -DZISK_DIR=/path/to/zisk (or ZISK_DIR env var) to a checkout of "
        "https://github.com/0xPolygonHermez/zisk.git")
endif()
if(NOT EXISTS "${_ziskos_staticlib}")
    message(FATAL_ERROR
        "libziskos_staticlib.a not found at ${_ziskos_staticlib}.\n"
        "Build it once with:\n"
        "    cd ${ZISK_DIR} && cargo +zisk build --release \\\n"
        "        --target=riscv64ima-zisk-zkvm-elf -p ziskos-staticlib\n"
        "(The `+zisk` rustup toolchain ships the riscv64ima-zisk-zkvm-elf "
        "target spec; plain `cargo` will fail with `error loading target specification`.)")
endif()

target_include_directories(z6m_guest.elf PRIVATE
    include
    ${Z6M_ROOT}/prover/host_lib/include   # z6m_dispatch.hpp (shared with host)
    ${_zkvm_interface_inc}                # zkvm_io.h (ziskos C ABI)
)

# Weaken the ziskos symbols that collide with our local guest runtime
# objects (_start.s, dma/*.s, memmove.cpp). Background:
#
#   ziskos-staticlib packs _start + memcpy/memset/memcmp/memmove + the
#   secp256k1 math helpers + Rust allocator hooks into one Rust codegen
#   unit (cgu.11.rcgu.o). The moment ld needs *anything* from that .o
#   (e.g. double_scalar_mul_with_g_secp256k1_c for zkvm ecrecover), it
#   pulls the whole thing in, which makes ziskos's _start collide with
#   ours.
#
# Solution: post-process the archive once, demoting the colliding symbols
# from strong global to weak. Our local strong definitions then win at
# link time; the rest of the .o (secp256k1 math etc.) comes in normally.
# No `--allow-multiple-definition` warnings, no edits to ziskos.
set(_ziskos_staticlib_filtered "${CMAKE_BINARY_DIR}/libziskos_staticlib.filtered.a")
add_custom_command(
    OUTPUT  "${_ziskos_staticlib_filtered}"
    COMMAND "${CMAKE_OBJCOPY}"
            --weaken-symbol=_start
            --weaken-symbol=memcpy
            --weaken-symbol=memset
            --weaken-symbol=memcmp
            --weaken-symbol=memmove
            "${_ziskos_staticlib}"
            "${_ziskos_staticlib_filtered}"
    DEPENDS "${_ziskos_staticlib}"
    COMMENT "Weakening ziskos staticlib symbols that collide with the guest's local runtime"
    VERBATIM
)
add_custom_target(ziskos_staticlib_filtered DEPENDS "${_ziskos_staticlib_filtered}")
add_dependencies(z6m_guest.elf ziskos_staticlib_filtered)

# silkworm_dev publicly links silkworm_core + nlohmann_json, which
# in turn propagates intx::intx / evmone / evmc include paths.
# The filtered ziskos staticlib provides read_input / write_output /
# zkvm_* symbols referenced by zkvm_io.h and evmone's zkvm crypto provider.
target_link_libraries(z6m_guest.elf PRIVATE
    silkworm_dev
    "${_ziskos_staticlib_filtered}"
)

# Per-function/data sections so the linker can drop anything unreferenced.
# libstdc++ pulls in ~1000 `__cxa_*` exception sites, ~40 `__muldf3` /
# `__eqdf2` FP helpers and ~200 newlib stdio entries via load-bearing
# header inclusions; with -fno-exceptions and no actual FP / stdio use at
# runtime, none of that is reachable from main() — but without
# -Wl,--gc-sections the linker keeps it all anyway.
target_compile_options(z6m_guest.elf PRIVATE
    -ffunction-sections
    -fdata-sections
    -flto
)

# -nostartfiles drops newlib's crt0 (which expects __global_pointer$ that
# the Zisk linker script doesn't provide); _start.s + zisk.ld take its
# place. We use our own _start (not ziskos's) because ziskos's skips the
# C++ .init_array iteration, and evmone has load-bearing static ctors.
target_link_options(z6m_guest.elf PRIVATE
    -nostartfiles
    -T ${CMAKE_CURRENT_SOURCE_DIR}/zisk.ld
    -Wl,--gc-sections
    -flto
)

# Re-link whenever the linker script changes.
set_property(TARGET z6m_guest.elf APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/zisk.ld
)
