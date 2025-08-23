[settings]
os=baremetal
arch=riscv32
compiler=gcc
compiler.version=13
compiler.libcxx=libstdc++11
compiler.cppstd=gnu20
build_type=Release

[conf]
tools.build:compiler_executables={"c": "riscv32-unknown-elf-gcc","cpp": "riscv32-unknown-elf-g++", "ar":"riscv32-unknown-elf-ar"}
tools.build:cflags=["-march=rv32im","-mabi=ilp32","-mcmodel=medany"]
tools.build:cxxflags=["-march=rv32im","-mabi=ilp32","-mcmodel=medany"]
tools.build:sharedlinkflags=["-march=rv32im","-mabi=ilp32","-Wl,--gc-sections"]

[buildenv]
CC=riscv32-unknown-elf-gcc
CXX=riscv32-unknown-elf-g++
AR=riscv32-unknown-elf-ar
RANLIB=riscv32-unknown-elf-ranlib

[options]
*:shared=False