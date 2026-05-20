// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0

// build.rs for prover_zisk.
//
// Locates the C++ guest ELF (built by `make z6m_guest_zisk` via CMake)
// and exports the env vars that zisk_sdk::load_program! expects:
//   ZISK_ELF_z6m_guest       — absolute path to the ELF
//   ZISK_ELF_HASH_Z6M_GUEST  — blake3 hex digest of the ELF bytes
//
// This mirrors what `cargo-zisk build` would set if the guest were a
// Rust crate. We supply them ourselves because our guest is C++.

use std::path::Path;

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let elf_path = Path::new(&manifest_dir)
        .join("../guest_zisk/build/z6m_guest.elf")
        .canonicalize()
        .expect("C++ guest ELF not found – run `make z6m_guest_zisk` first");

    let elf_bytes = std::fs::read(&elf_path).expect("failed to read guest ELF");
    let hash = blake3::hash(&elf_bytes).to_hex().to_string();

    println!("cargo:rerun-if-changed={}", elf_path.display());
    println!("cargo:rustc-env=ZISK_ELF_z6m_guest={}", elf_path.display());
    println!("cargo:rustc-env=ZISK_ELF_HASH_z6m_guest={}", hash);
}
