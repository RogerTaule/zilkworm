// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0

// Zilkworm prover service — Zisk backend, milestone 1 (execute only).
//
// Mirrors the API surface of prover_hypercube/src/service.rs so the
// existing CLI plumbing (z6m_prover execute ...) keeps working. Only
// the Execute path is implemented for milestone 1 — Prove / Verify
// return an error directing the user to keep using prover_hypercube
// until Zisk proving is wired up.
//
// Two execution paths exist in zisk-sdk:
//   - zisk_sdk::run(&program, stdin, None)         — fast emulator,
//     no setup, no public-value capture. Equivalent to `cargo-zisk run`.
//   - ProverClient::embedded().build()?.execute(...) — full pipeline
//     minus the proof. Reports execution_steps / total_cost and the
//     public values. Auto-runs program setup on first call per ELF.
//     Equivalent to `cargo-zisk execute`.
//
// We use the `execute` path so we can populate executionLogs.log with
// the same fields zilkworm-hypercube logs today (gas_used + steps).

use crate::stdin_builders::{build_stdin_from_eth_tests, build_stdin_from_unified_rlp};
use eyre::{bail, Result};
use serde::Serialize;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use tracing::info;
use zisk_sdk::{load_program, GuestProgram, ProverClient, ZiskStdin};

/// Compile-time embed of the C++ guest ELF.
///
/// `ZISK_ELF_Z6M_GUEST` / `ZISK_ELF_HASH_Z6M_GUEST` are set by build.rs.
/// The macro reads those env vars and bakes the ELF bytes + hash into
/// the host binary so we don't touch disk at runtime.
static PROGRAM: GuestProgram = load_program!("z6m_guest");

#[derive(Clone, Debug)]
pub struct ExecuteOptions {
    pub block_number: u64,
    pub file_name: Option<PathBuf>,
    pub is_test: bool,
    pub data_dir: PathBuf,
}

#[derive(Clone, Debug, Serialize)]
pub struct ExecutionLog {
    pub block_number: u64,
    pub gas_used: u64,
    pub execution_steps: u64,
    pub total_cost: u64,
    pub input_path: PathBuf,
}

pub struct Z6mProverZiskService;

impl Z6mProverZiskService {
    pub async fn execute_block_static(opts: ExecuteOptions) -> Result<ExecutionLog> {
        let input_path = Self::resolve_input_path(
            opts.block_number,
            opts.file_name.clone(),
            opts.is_test,
            &opts.data_dir,
        )?;
        if !input_path.exists() {
            bail!(
                "input file for block {} not found at {}",
                opts.block_number,
                input_path.display()
            );
        }

        let input_bytes = if opts.is_test {
            build_stdin_from_eth_tests(&input_path)?
        } else {
            build_stdin_from_unified_rlp(&input_path)?
        };

        // Use the full pipeline path (minus proof generation) so we get
        // structured ExecuteResult metrics back. Auto-runs program setup
        // on first call per ELF — requires ~/.zisk proving keys to match
        // the SDK version (we built against v0.17.0; the user's keys
        // must be v0.17.0 too).
        let client = ProverClient::embedded()
            .build()
            .map_err(|e| eyre::eyre!("ProverClient build: {e}"))?;

        // One-time program setup per ELF — derives the program key and
        // caches it. Subsequent execute() calls reuse the cached entry.
        // The docs claim execute() auto-runs setup if the program isn't
        // cached, but v0.17.0 actually errors with "Program 'name' not
        // found in cache" — we have to call setup() explicitly.
        client
            .setup(&PROGRAM)
            .run()
            .map_err(|e| eyre::eyre!("setup submit: {e}"))?
            .await
            .map_err(|e| eyre::eyre!("setup await: {e}"))?;

        // We already framed the input ourselves; feed those raw bytes
        // through ZiskStdin::from_bytes which DOES NOT re-frame (it just
        // wraps the buffer as-is — see common/src/io/stdin/zisk_stdin.rs::from_vec).
        let stdin = ZiskStdin::from_bytes(input_bytes);

        let handle = client
            .execute(&PROGRAM, stdin)
            .run()
            .map_err(|e| eyre::eyre!("execute submit: {e}"))?;
        let result = handle.await.map_err(|e| eyre::eyre!("execute await: {e}"))?;

        // ExecuteResult derefs to ExecuteOutput; method names from
        // /tmp/zisk-v0.17.0/prover-backend/src/output.rs.
        let execution_steps = result.get_execution_steps();
        let total_cost      = result.get_execution_cost();

        // Public values: first 8 bytes are gas_used as little-endian u64
        // (see guest_zisk/src/main.cpp::set_output_u64).
        let mut pv_buf = [0u8; 8];
        result.get_public_values_slice(&mut pv_buf);
        let gas_used = u64::from_le_bytes(pv_buf);

        info!(
            "execution complete, block={} gas_used={}, steps={}, cost={}",
            opts.block_number, gas_used, execution_steps, total_cost
        );

        let log = ExecutionLog {
            block_number: opts.block_number,
            gas_used,
            execution_steps,
            total_cost,
            input_path: input_path.clone(),
        };
        let log_file = opts.data_dir.join("executionLogs.log");
        Self::persist_execution_logs(&log_file, &log)?;
        Ok(log)
    }

    fn resolve_input_path(
        block_number: u64,
        file_name: Option<PathBuf>,
        is_test: bool,
        data_dir: &Path,
    ) -> Result<PathBuf> {
        if let Some(file) = file_name {
            return Ok(file);
        }
        if block_number == 0 {
            bail!("must provide --block-number > 0 or explicit input file");
        }
        let dir = data_dir.join("blocks").join(block_number.to_string());
        let file_name = if is_test {
            format!("ethTests{}.json", block_number)
        } else {
            format!("unifiedBlockAndStateRlp{}.bin", block_number)
        };
        Ok(dir.join(file_name))
    }

    fn persist_execution_logs(log_file: &Path, log: &ExecutionLog) -> Result<()> {
        if let Some(parent) = log_file.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }
        let mut f = OpenOptions::new().create(true).append(true).open(log_file)?;
        let ts = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.6fZ");
        writeln!(
            &mut f,
            "[{}] block {} executed, gas_used={}, steps={}, cost={}, input={}",
            ts,
            log.block_number,
            log.gas_used,
            log.execution_steps,
            log.total_cost,
            log.input_path.display()
        )?;
        Ok(())
    }
}
