### Installing SP1 toolchain

Install sp1 and its c-toolchain
see https://docs.succinct.xyz/docs/sp1/getting-started/install
```
curl -L https://sp1up.succinct.xyz | bash
source ~/.bashrc
sp1up --c-toolchain
```

### Directory for pre-built libs for riscv32im

Download the tar
```
wget https://github.com/somnathb1/cppsp1explorations/raw/ebc1da3252da1f6c9547fb99f5029acd0e296567/riscv32im_filtered_gcc_stdcpp_libs.tar.gz
```

Untar the tar containing the libs here in place
```
tar --strip-components=1 -xzf riscv32im_filtered_gcc_stdcpp_libs.tar.gz
```


You should point the g++ to the one provided by the installation of sp1up, for the rv32im-ilp32 arch/platform
(Replace directory names according to your installation in the following)
```sh
export RUSTC_LINKER=~/.sp1/riscv/riscv32im-linux-x86_64/bin/riscv32-unknown-elf-ld 
export CXX_riscv32im_succinct_zkvm_elf=~/.sp1/riscv/riscv32im-linux-x86_64/bin/riscv32-unknown-elf-g++ 
export CONAN_PROFILE_HOST=riscv32-baremetal
```


export CXX_riscv32im_unknown_none_elf=~/.sp1/riscv/riscv32im-linux-x86_64/bin/riscv32-unknown-elf-g++


export CC_riscv32im_unknown_none_elf="riscv32-unknown-elf-gcc"
export CXX_riscv32im_unknown_none_elf="riscv32-unknown-elf-g++"
export AR_riscv32im_unknown_none_elf="riscv32-unknown-elf-ar"
export CFLAGS_riscv32im_unknown_none_elf="--specs=nosys.specs -ffunction-sections -fdata-sections"
export CXXFLAGS_riscv32im_unknown_none_elf="-fno-exceptions -fno-rtti -ffunction-sections -fdata-sections"

export CMAKE_C_COMPILER=riscv32-unknown-elf-gcc 
export CMAKE_CXX_COMPILER=riscv32-unknown-elf-g++
export CMAKE_ASM_COMPILER=riscv32-unknown-elf-gcc

Quick cmd
```
### Execute
rm -rf ../target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* && cargo prove build && RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --execute

### Prove AMD Zen4
rm -rf ../target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* && cargo prove build && RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --prove
```

AMD AVX
```
rm -rf ../target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* && cargo prove build && RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --prove

rm -rf ../target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* && cargo prove build && RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --execute


RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --prove
```

```
SP1_PROVER=cuda RUST_BACKTRACE=full RUST_LOG=info cargo run --release -- --prove

```