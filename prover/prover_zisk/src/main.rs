// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0

mod service;
mod stdin_builders;

use crate::service::{ExecuteOptions, Z6mProverZiskService};
use clap::{Parser, Subcommand};
use eyre::{bail, eyre, Result};
use std::path::PathBuf;
use tracing_subscriber::{fmt, EnvFilter};
use z6m_common::{fetch_block_and_witness, FetchRequest};

#[derive(Parser, Debug)]
#[command(name = "z6m_prover", about = "Zilkworm prover service (Zisk backend)")]
struct Args {
    #[arg(long)]
    rpc_url: Option<String>,

    /// Root data directory containing a blocks/ subdirectory.
    #[arg(long, default_value = "temp")]
    data_dir: PathBuf,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Fetch block and witness from RPC.
    Fetch {
        #[arg(long)]
        rpc_url: Option<String>,
        #[arg(long)]
        block_number: Option<u64>,
        #[arg(long)]
        data_dir: Option<PathBuf>,
        #[arg(long, action = clap::ArgAction::SetTrue)]
        save_all_responses: bool,
        #[arg(long, action = clap::ArgAction::SetTrue)]
        build_eth_test: bool,
        #[arg(long, action = clap::ArgAction::SetTrue)]
        geth: bool,
    },
    /// Execute the guest program without proving.
    Execute {
        #[arg(long, default_value_t = 0)]
        block_number: u64,
        #[arg(long)]
        file_name: Option<PathBuf>,
        #[arg(long, action = clap::ArgAction::SetTrue)]
        is_test: bool,
        #[arg(long)]
        data_dir: Option<PathBuf>,
    },
    /// Generate a proof (not yet supported on Zisk — milestone 2).
    Prove,
    /// Verify a proof (not yet supported on Zisk — milestone 2).
    Verify,
}

#[tokio::main]
async fn main() -> Result<()> {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn"));
    fmt().with_env_filter(filter).init();
    dotenv::dotenv().ok();
    let args = Args::parse();

    match args.command {
        Some(Command::Fetch {
            rpc_url,
            block_number,
            data_dir,
            save_all_responses,
            build_eth_test,
            geth,
        }) => {
            let rpc = rpc_url
                .or_else(|| args.rpc_url.clone())
                .ok_or_else(|| eyre!("fetch requires --rpc-url"))?;
            let outcome = fetch_block_and_witness(FetchRequest {
                block_number,
                rpc_url: &rpc,
                save_all_responses,
                data_dir: data_dir.unwrap_or_else(|| args.data_dir.clone()),
                build_eth_test,
                geth,
            })
            .await?;
            println!(
                "Fetched block {} into {}",
                outcome.block_number,
                outcome.block_directory.display()
            );
        }
        Some(Command::Execute {
            block_number,
            file_name,
            is_test,
            data_dir,
        }) => {
            let opts = ExecuteOptions {
                block_number,
                file_name,
                is_test,
                data_dir: data_dir.unwrap_or_else(|| args.data_dir.clone()),
            };
            let log = Z6mProverZiskService::execute_block_static(opts).await?;
            println!(
                "Executed block {} (gas_used={}, steps={}, cost={})",
                log.block_number, log.gas_used, log.execution_steps, log.total_cost
            );
        }
        Some(Command::Prove) | Some(Command::Verify) => {
            bail!("Zisk backend currently supports only `execute` — use prover_hypercube for proving.");
        }
        None => {
            bail!("no command provided; pass a subcommand (fetch | execute)");
        }
    }

    Ok(())
}
