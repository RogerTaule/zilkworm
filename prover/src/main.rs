//! SP1 prover CLI with block fetching and witness conversion

pub mod fetcher;
pub mod types;

use clap::Parser;
use sp1_sdk::{
    include_elf, ProverClient, SP1ProofWithPublicValues, SP1ProvingKey, SP1VerifyingKey,
};
use std::{
    fs,
    io::{BufReader, BufWriter},
    path::PathBuf,
};

// Import alloy types (updated for 1.0)
use eyre::{bail, Result};

use crate::fetcher::{build_stdin_from_eth_tests, fetch_block_and_witness};

/// The ELF file for the zkVM
pub const SILK_ST_ELF: &[u8] = include_elf!("z6m_guest");

#[derive(Parser, Debug)]
#[command(name = "silk-prover", about = "SP1 prover with block fetching")]
struct Args {
    /// Operation mode
    #[command(subcommand)]
    command: Command,
}

#[derive(Parser, Debug)]
enum Command {
    /// Run setup to generate proving and verifying keys
    Setup {
        /// File path to save proving key
        #[arg(long, default_value = "pk.bin")]
        pk_path: String,
        /// File path to save verifying key
        #[arg(long, default_value = "vk.bin")]
        vk_path: String,
    },

    /// Fetch block and witness from RPC
    Fetch {
        /// RPC endpoint URL
        #[arg(long)]
        rpc_url: String,
        /// Block number to fetch
        #[arg(long)]
        block_number: u64,
        /// Output directory
        #[arg(long, default_value = "temp")]
        data_dir: PathBuf,
    },

    /// Execute the guest program without proving
    Execute {
        /// Block number to execute
        #[arg(long, default_value = "0")]
        block_number: u64,

        #[arg(long)]
        file_name: String,

        /// Data directory
        #[arg(long, default_value = "temp")]
        data_dir: PathBuf,
    },

    /// Generate a proof for a block
    Prove {
        /// Block number to execute
        #[arg(long, default_value = "0")]
        block_number: u64,

        /// JSON file to load ethereum/tests format test from
        #[arg(long)]
        file_name: String,

        /// Data directory
        #[arg(long, default_value = "data")]
        data_dir: PathBuf,
        /// Proving key path
        #[arg(long, default_value = "pk.bin")]
        pk_path: String,
        /// Proof output path
        #[arg(long, default_value = "proof.bin")]
        proof_path: String,
    },

    /// Verify a proof
    Verify {
        /// Proof file path
        #[arg(long, default_value = "proof.bin")]
        proof_path: String,
        /// Verifying key path
        #[arg(long, default_value = "vk.bin")]
        vk_path: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logger and environment
    sp1_sdk::utils::setup_logger();
    dotenv::dotenv().ok();

    let args = Args::parse();

    match args.command {
        Command::Setup { pk_path, vk_path } => {
            setup(pk_path, vk_path)?;
        }
        Command::Fetch {
            rpc_url,
            block_number,
            data_dir,
        } => {
            fetch_block_and_witness(rpc_url, block_number, data_dir).await?;
        }
        Command::Execute {
            block_number,
            file_name,
            data_dir,
        } => {
            execute_block(block_number, file_name, data_dir)?;
        }
        Command::Prove {
            block_number,
            file_name,
            data_dir,
            pk_path,
            proof_path,
        } => {
            prove_block(block_number, file_name, data_dir, pk_path, proof_path)?;
        }
        Command::Verify {
            proof_path,
            vk_path,
        } => {
            verify_proof(proof_path, vk_path)?;
        }
    }

    Ok(())
}

fn setup(pk_path: String, vk_path: String) -> Result<()> {
    let client = ProverClient::from_env();
    let (pk, vk) = client.setup(SILK_ST_ELF);

    std::fs::create_dir_all(".").unwrap();

    let cfg = bincode::config::standard();
    let mut fpk = BufWriter::new(fs::File::create(&pk_path)?);
    bincode::serde::encode_into_std_write(&pk, &mut fpk, cfg)?;

    let mut fvk = BufWriter::new(fs::File::create(&vk_path)?);
    bincode::serde::encode_into_std_write(&vk, &mut fvk, cfg)?;

    println!(
        "Setup completed. Saved pk -> {}, vk -> {}",
        pk_path, vk_path
    );
    Ok(())
}

fn execute_block(block_number: u64, file_name: String, data_dir: PathBuf) -> Result<()> {
    let client = ProverClient::from_env();
    let file_path;
    if file_name.is_empty() {
        if block_number == 0 {
            bail!("Must pecify --file-name or --block-number > 0")
        }
        file_path = data_dir.join(format!("{}/ethTests{}.json", block_number, block_number));
    } else {
        file_path = file_name.into();
    }

    if !file_path.exists() {
        bail!(
            "Test file not found: {}. Run 'fetch' first.",
            file_path.display()
        );
    }

    let mut stdin = build_stdin_from_eth_tests(&file_path)?;
    let (mut output, report) = client.execute(SILK_ST_ELF, &stdin).run().unwrap();

    println!("Program executed successfully.");
    println!("Cumulative Gas Used: {}", output.read::<u64>());
    println!("Number of cycles: {}", report.total_instruction_count());

    Ok(())
}

fn prove_block(
    block_number: u64,
    file_name: String,
    data_dir: PathBuf,
    pk_path: String,
    proof_path: String,
) -> Result<()> {
    let client = ProverClient::from_env();
    let cfg = bincode::config::standard();

    // Load proving key
    let pk: SP1ProvingKey = {
        let mut r = BufReader::new(fs::File::open(&pk_path)?);
        bincode::serde::decode_from_std_read(&mut r, cfg)?
    };

    // Load test data
    let file_path;
    if file_name.is_empty() {
        if block_number == 0 {
            bail!("Must pecify --file-name or --block-number > 0")
        }
        println!("Requested proof for block {}...", block_number);
        file_path = data_dir.join(format!("{}/ethTests{}.json", block_number, block_number));
    } else {
        file_path = file_name.into();
    }

    if !file_path.exists() {
        bail!(
            "Test file not found: {}. Run 'fetch' first.",
            file_path.display()
        );
    }

    let mut stdin = build_stdin_from_eth_tests(&file_path)?;

    println!("Starting Proof Generation");
    let mut proof = client.prove(&pk, &stdin).run().unwrap();

    println!("Successfully generated proof!");
    println!("Cumulative Gas Used: {}", proof.public_values.read::<u64>());

    // Save proof
    let mut fp = BufWriter::new(fs::File::create(&proof_path)?);
    bincode::serde::encode_into_std_write(&proof, &mut fp, cfg)?;
    println!("Saved proof -> {}", proof_path);

    Ok(())
}

fn verify_proof(proof_path: String, vk_path: String) -> Result<()> {
    let cfg = bincode::config::standard();

    let mut proof: SP1ProofWithPublicValues = {
        let mut r = BufReader::new(fs::File::open(&proof_path)?);
        bincode::serde::decode_from_std_read(&mut r, cfg)?
    };

    let vk: SP1VerifyingKey = {
        let mut r = BufReader::new(fs::File::open(&vk_path)?);
        bincode::serde::decode_from_std_read(&mut r, cfg)?
    };

    ProverClient::from_env().verify(&proof, &vk)?;

    println!("Successfully verified proof!");
    println!("Cumulative Gas Used: {}", proof.public_values.read::<u64>());

    Ok(())
}
