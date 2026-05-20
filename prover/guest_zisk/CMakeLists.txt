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

add_executable(hello.elf
    hello.cpp
    arena_malloc.cpp
    runtime_stubs.cpp
    memcpy.cpp
    memmove.cpp
    _start.s
)

target_include_directories(hello.elf PRIVATE include)
# silkworm_dev publicly links silkworm_core + nlohmann_json, which
# in turn propagates intx::intx / evmone / evmc include paths.
target_link_libraries(hello.elf PRIVATE silkworm_dev)

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
