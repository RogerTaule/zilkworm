Install sp1 and its c-toolchain
see https://docs.succinct.xyz/docs/sp1/getting-started/install
```
curl -L https://sp1up.succinct.xyz | bash
source ~/.bashrc
sp1up --c-toolchain
```


You should point the g++ to the one provided by the installation of sp1up, for the rv32im-ilp32 arch/platform
(Replace directory names according to your installation in the following)
```sh
export RUSTC_LINKER=~/.sp1/riscv/riscv32im-linux-x86_64/bin/riscv32-unknown-elf-ld 
export CXX_riscv32im_succinct_zkvm_elf=~/.sp1/riscv/riscv32im-linux-x86_64/bin/riscv32-unknown-elf-g++ 
export CONAN_PROFILE_HOST=riscv32-baremetal
```

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