

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo_224_80_white.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo_224_80.svg">
    <img alt="Project Logo" src="docs/assets/logo-light.png" width="320">
  </picture>
</p>

<p align="center">
    A fast, modular, optimized ZKEVM core written in C++
</p>

[NOTE: THIS IS A WORK IN PROGRESS REPOSITORY THAT MAY LACK MAINTENANCE, AND IS PROVIDED AS IS. DO NOT USE IN PRODUCTION ]


Zilkworm is a prototype implementation of a ZKEVM building on past works within Silkworm and EVMOne to run on ZKVM provers with native support for RISC-V targets (e.g. rv32im). 
At the moment the ZKVM integrated is Succint's SP1 Turbo.

## Testing

### Native build
Make sure to install applicable tools (g++ 15.2.x, CMAKE, git, git-lfs) and ctest before running the tests:
```
make eest-blockchain-tests
```
## Acknowledgements
We thank the hard work done by the teams and people behind
1. Silkworm
2. EVMOne (especially @chfast)
3. Succicnt (for SP1 and rsp)
4. RISCV
5. C++ Conglomerate
6. The Rust community

