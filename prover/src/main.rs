//! An end-to-end example of using the SP1 SDK to generate a proof of a program that can be executed
//! or have a core proof generated.
//!
//! You can run this script using the following command:
//! ```shell
//! RUST_LOG=info cargo run --release -- --execute
//! ```
//! or
//! ```shell
//! RUST_LOG=info cargo run --release -- --prove
//! ```

use alloy_sol_types::SolType;
use clap::Parser;
// use fibonacci_lib::PublicValuesStruct;
use sp1_sdk::{include_elf, Prover, ProverClient, SP1Stdin};
use std::fs;

/// The ELF (executable and linkable format) file for the Succinct RISC-V zkVM.
pub const SILK_ST_ELF: &[u8] = include_elf!("z6m_guest");

/// The arguments for the command.
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(long)]
    execute: bool,

    #[arg(long)]
    prove: bool,

    #[arg(long, default_value = "1")]
    n: u32,

    #[arg(long, default_value = "test.json")]
    file_name: String,
}

fn main() {
    // Setup the logger.
    sp1_sdk::utils::setup_logger();
    dotenv::dotenv().ok();

    // Parse the command line arguments.
    let args = Args::parse();

    if args.execute == args.prove {
        eprintln!("Error: You must specify either --execute or --prove");
        std::process::exit(1);
    }

    // Setup the prover client.
    let client = ProverClient::from_env();
    let mut stdin = SP1Stdin::new();
    stdin.write(&args.n);

    let test_json_raw = fs::read_to_string(&args.file_name).expect("failed to read file");
    let test_json_value: serde_json::Value = serde_json::from_str(&test_json_raw).expect("invalid JSON");
    let test_json = serde_json::to_string(&test_json_value).expect("failed to minify JSON");
    let test_json_bytes = test_json.as_bytes();
    stdin.write_slice(test_json_bytes);

    println!("n: {}", args.n);
    println!("Input len: {}", test_json.len());

    if args.execute {
        // Execute the program
        let (mut output, report) = client.execute(SILK_ST_ELF, &stdin).run().unwrap();
        println!("Program executed successfully.");
        println!("Cumulative Gas Used: {}", output.read::<u64>()) ;

        // Record the number of cycles executed.
        println!("Number of cycles: {}", report.total_instruction_count());
    } else {
        // Setup the program for proving.
        let (pk, vk) = client.setup(SILK_ST_ELF);

        // Generate the proof
        let mut proof = client
            .prove(&pk, &stdin)
            .run()
            .expect("failed to generate proof");

        println!("Successfully generated proof!");

        // Verify the proof.
        client.verify(&proof, &vk).expect("failed to verify proof");
        println!("Successfully verified proof!");
        println!("Cumulative Gas Used: {}", proof.public_values.read::<u64>()) ;

    }
}
