[settings]
os=baremetal
arch=riscv32
compiler=riscv-none-elf-gcc
compiler.version=15
compiler.libcxx=libstdc++11
compiler.cppstd=gnu23
build_type=Release

[conf]
tools.build:compiler_executables={"c": "riscv-none-elf-gcc","cpp": "riscv-none-elf-g++", "ar":"riscv-none-elf-ar"}
tools.build:cflags=["-march=rv32im","-mabi=ilp32","-mcmodel=medany"]
tools.build:cxxflags=["-march=rv32im","-mabi=ilp32","-mcmodel=medany"]
tools.build:sharedlinkflags=["-march=rv32im","-mabi=ilp32","-Wl,--gc-sections"]

[buildenv]
CC=riscv-none-elf-gcc
CXX=riscv-none-elf-g++
AR=riscv-none-elf-ar
RANLIB=riscv-none-elf-ranlib

[options]
*:shared=False