# Zisk guest POC — minimal C++ program that runs under the Zisk zkVM.
#
# Configure with the toolchain file:
#   cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE=cmake/zisk-toolchain.cmake
#   cmake --build build
# Output: build/z6m_guest.elf — run with `ziskemu -e build/z6m_guest.elf -i <input.bin>`.

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
    memmove.cpp
    _start.s
    # DMA-accelerated mem ops: memcpy / memset / memcmp via Zisk CSR
    # syscalls 0x813 / 0x816 / 0x814. Each routine is 2–3 instructions
    # vs the ~150-line musl-derived assembly memcpy.cpp we previously
    # used. Sourced as-is from ziskos/entrypoint/src/dma/*.s.
    dma/memcpy.s
    dma/memset.s
    dma/memcmp.s
    # Override libgcc's software multiply/divide/clz/ctz/popcount helpers
    # with versions that lower to native rv64IM instructions. The xPack
    # toolchain picks the rv64ia libgcc multilib for our -march and thus
    # ships software shift-and-add helpers; this file shadows them.
    libgcc_overrides.cpp
    # Zisk syscall overrides for evmone precompiles. Each file defines an
    # extern "C" entry point that evmone's portable precompile code routes
    # to via `#elif defined(ZISK)` gates.
    precompiles/zisk_sha256.cpp
)

target_include_directories(z6m_guest.elf PRIVATE include)
# silkworm_dev publicly links silkworm_core + nlohmann_json, which
# in turn propagates intx::intx / evmone / evmc include paths.
target_link_libraries(z6m_guest.elf PRIVATE silkworm_dev)

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
# the Zisk linker script doesn't provide); _start.s + zisk.ld take its place.
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
