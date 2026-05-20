// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0

// Build the unframed payload bytes for the C++ guest.
//
// We feed these to ZiskStdin via from_bytes/write_slice which adds the
// [u64 LE length][padding] framing internally (see
// /tmp/zisk-v0.17.0/common/src/io/stdin/zisk_stdin.rs::write_slice).
// The emulator places the framed buffer at INPUT_ADDR + 8 (after its
// own 8-byte free_input header at INPUT_ADDR + 0).
//
// Payload layout matched to prover/guest_zisk/src/main.cpp::main():
//   byte 0:       is_test flag (0 = unified RLP, 1 = ethereum/tests JSON)
//   bytes 1..n:   contents

use eyre::Result;
use std::fs;
use std::path::Path;

pub fn build_stdin_from_eth_tests(path: &Path) -> Result<Vec<u8>> {
    let raw = fs::read_to_string(path)?;
    // Minify the JSON to match the prover_hypercube behaviour and shrink the input region.
    let value: serde_json::Value = serde_json::from_str(&raw)?;
    let minified = serde_json::to_string(&value)?;

    let mut payload = Vec::with_capacity(1 + minified.len());
    payload.push(1u8);                          // is_test = true
    payload.extend_from_slice(minified.as_bytes());

    Ok(payload)
}

pub fn build_stdin_from_unified_rlp(path: &Path) -> Result<Vec<u8>> {
    let raw = fs::read(path)?;

    let mut payload = Vec::with_capacity(1 + raw.len());
    payload.push(0u8);                          // is_test = false
    payload.extend_from_slice(&raw);

    Ok(payload)
}
