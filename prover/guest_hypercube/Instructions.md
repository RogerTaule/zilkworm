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

AMD AVX
```
rm -rf ../target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* && cargo prove build && RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --prove

rm -rf ../target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* && cargo prove build && RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --execute


RUSTFLAGS="-C target-cpu=znver3" RUST_BACKTRACE=full RUST_LOG=info cargo run --release --manifest-path ../prover/Cargo.toml -- --prove
```

```
SP1_PROVER=cuda RUST_BACKTRACE=full RUST_LOG=info cargo run --release -- --prove

```


##### FOR HYPERCUBE ###########

CC_riscv64im_succinct_zkvm_elf

export RUSTC_LINKER=riscv-none-elf-ld 
export CC_riscv64im_succinct_zkvm_elf=/usr/bin/riscv-none-elf-g++
export CXX_riscv64im_succinct_zkvm_elf=/usr/bin/riscv-none-elf-g++
export CONAN_PROFILE_HOST=riscv64-baremetal


export RUSTC_LINKER=riscv-none-elf-ld 
export CC_riscv64im_succinct_zkvm_elf=riscv-none-elf-gcc
export CXX_riscv64im_succinct_zkvm_elf=riscv-none-elf-g++
export CONAN_PROFILE_HOST=riscv64-baremetal