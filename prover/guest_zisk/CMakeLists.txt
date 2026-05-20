# Zisk guest POC — minimal C++ program that runs under the Zisk zkVM.
#
# Configure with the toolchain file:
#   cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE=cmake/zisk-toolchain.cmake
#   cmake --build build
# Output: build/hello.elf — run with `ziskemu -e build/hello.elf -i <input.bin>`.

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

include(CableBuildInfo)
cable_add_buildinfo_library(PROJECT_NAME zilkworm GIT_DESCRIBE "" GIT_BRANCH "")

# Pull in the real third_party targets: intx::intx, evmc, evmone, blst::blst.
# The local evmone_keccak / zilk_core_common targets from L1 stay in place
# below for now — they will be retired once silkworm_core is wired up.
add_subdirectory(${Z6M_ROOT}/third_party ${CMAKE_BINARY_DIR}/third_party)

# L1 — start pulling zilk_core's common/ sources in as a static lib.

# evmone_precompiles/keccak.hpp declares
#   static constexpr auto keccak256_32 = ethash_keccak256_32;
# which is referenced from any TU that transitively includes keccak.hpp.
# Compile the matching C definition so the relocation resolves at link time.
add_library(evmone_keccak STATIC
    ${Z6M_ROOT}/third_party/evmone/lib/evmone_precompiles/keccak.c
)
target_include_directories(evmone_keccak PUBLIC
    ${Z6M_ROOT}/third_party/evmone/lib
)

add_library(zilk_core_common STATIC
    ${Z6M_ROOT}/zilk_core/core/common/assert.cpp
    ${Z6M_ROOT}/zilk_core/core/common/endian.cpp
    ${Z6M_ROOT}/zilk_core/core/common/util.cpp
)

target_include_directories(zilk_core_common PUBLIC
    ${Z6M_ROOT}
    ${Z6M_ROOT}/third_party/intx/include
    ${Z6M_ROOT}/third_party/evmone/evmc/include
)
target_link_libraries(zilk_core_common PUBLIC evmone_keccak)

add_executable(hello.elf
    hello.cpp
    arena_malloc.cpp
    runtime_stubs.cpp
    _start.s
)

target_include_directories(hello.elf PRIVATE include)
target_link_libraries(hello.elf PRIVATE zilk_core_common)

# -nostartfiles drops newlib's crt0 (which expects __global_pointer$ that
# the Zisk linker script doesn't provide); _start.s + zisk.ld take its place.
target_link_options(hello.elf PRIVATE
    -nostartfiles
    -T ${CMAKE_CURRENT_SOURCE_DIR}/zisk.ld
)

# Re-link whenever the linker script changes.
set_property(TARGET hello.elf APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/zisk.ld
)
