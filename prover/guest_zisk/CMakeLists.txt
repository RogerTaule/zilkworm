# Zisk guest POC — minimal C++ program that runs under the Zisk zkVM.
#
# Configure with the toolchain file:
#   cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE=cmake/zisk-toolchain.cmake
#   cmake --build build
# Output: build/hello.elf — run with `ziskemu -e build/hello.elf -i <input.bin>`.

cmake_minimum_required(VERSION 3.20)
project(zisk_guest_poc LANGUAGES C CXX ASM)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(hello.elf
    hello.cpp
    arena_malloc.cpp
    runtime_stubs.cpp
    _start.s
)

# intx is header-only — point at its include dir directly to avoid pulling
# in the rest of zilk_core's build graph at this milestone.
target_include_directories(hello.elf PRIVATE
    include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/intx/include
)

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
