use crate::ethproofs_client::{EthProofsConfig, EthproofsClient};
use crate::fetcher::{
    build_stdin_from_eth_tests, build_stdin_from_unified_rlp, fetch_block_and_witness,
    FetchOutcome, FetchRequest,
};
use alloy_provider::{Provider, ProviderBuilder};
use eyre::{bail, Context, Result};

use chrono;
use serde::Serialize;
use sp1_sdk::{
    include_elf, EnvProver, ProverClient, SP1ProofWithPublicValues, SP1ProvingKey, SP1Stdin,
    SP1VerifyingKey,
};
use std::fs::{self, File, OpenOptions};
use std::io::{BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;
use tokio::time::sleep;
use tracing::{error, info, warn};
use url::Url;

pub const SILK_ST_ELF: &[u8] = include_elf!("z6m_guest");

#[derive(Clone, Debug)]
pub struct AppConfig {
    pub data_dir: PathBuf,
    pub rpc_url: Option<String>,
    pub websocket_url: Option<String>,
    pub save_all_responses: bool,
    pub ethproofs: Option<EthProofsConfig>,
}

#[derive(Clone, Debug)]
pub struct ServiceConfig {
    pub start_block: Option<u64>,
    pub prove_every: Option<u64>,
    pub execute_every: Option<u64>,
    pub post_every: Option<u64>,
    pub rpc_url: String,
    pub save_all_responses: bool,
    pub proving_key_path: Option<PathBuf>,
    pub proof_type: String,
}

#[derive(Clone, Debug)]
pub struct SetupOptions {
    pub pk_path: PathBuf,
    pub vk_path: PathBuf,
}

#[derive(Clone, Debug)]
pub struct FetchOptions {
    pub block_number: Option<u64>,
    pub rpc_url: String,
    pub save_all_responses: bool,
    pub data_dir: PathBuf,
    pub build_eth_test: bool,
}

#[derive(Clone, Debug)]
pub struct ExecuteOptions {
    pub block_number: u64,
    pub file_name: Option<PathBuf>,
    pub is_test: bool,
    pub data_dir: PathBuf,
}

#[derive(Clone, Debug)]
pub struct ProveOptions {
    pub block_number: u64,
    pub file_name: Option<PathBuf>,
    pub is_test: bool,
    pub data_dir: PathBuf,
    pub pk_path: PathBuf,
    pub proof_path: Option<PathBuf>,
    pub proof_type: String,
}

#[derive(Clone, Debug)]
pub struct VerifyOptions {
    pub proof_path: PathBuf,
    pub vk_path: PathBuf,
}

#[derive(Clone, Debug, Serialize)]
pub struct ExecutionLog {
    pub block_number: u64,
    pub gas_used: u64,
    pub cycle_count: u64,
    pub input_path: PathBuf,
}

#[derive(Clone, Debug, Serialize)]
pub struct ProvingLog {
    pub block_number: u64,
    pub gas_used: u64,
    pub proof_path: PathBuf,
    pub proof_type: String,
    pub proving_millis: u64,
    pub message: String,
}

pub struct Z6mProverService {
    client: Arc<Mutex<EnvProver>>,
    config: AppConfig,
    eth_client: Option<EthproofsClient>,
}

impl Z6mProverService {
    fn format_timestamp() -> String {
        chrono::Utc::now()
            .format("%Y-%m-%dT%H:%M:%S%.6fZ")
            .to_string()
    }

    pub fn new(config: AppConfig) -> Result<Self> {
        let client = Arc::new(Mutex::new(ProverClient::from_env()));
        let eth_client = config
            .ethproofs
            .clone()
            .map(EthproofsClient::new)
            .transpose()?;
        Ok(Self {
            client,
            config,
            eth_client,
        })
    }

    pub async fn setup_keys(&self, opts: SetupOptions) -> Result<()> {
        let client = self.client.lock().await;
        let (pk, vk) = client.setup(SILK_ST_ELF);
        std::fs::create_dir_all(opts.pk_path.parent().unwrap_or_else(|| Path::new(".")))?;
        std::fs::create_dir_all(opts.vk_path.parent().unwrap_or_else(|| Path::new(".")))?;
        let cfg = bincode::config::standard();
        let mut fpk = BufWriter::new(File::create(&opts.pk_path)?);
        bincode::serde::encode_into_std_write(&pk, &mut fpk, cfg)?;
        let mut fvk = BufWriter::new(File::create(&opts.vk_path)?);
        bincode::serde::encode_into_std_write(&vk, &mut fvk, cfg)?;
        info!(
            "setup completed: pk={}, vk={}",
            opts.pk_path.display(),
            opts.vk_path.display()
        );
        Ok(())
    }

    pub async fn fetch_block(&self, opts: FetchOptions) -> Result<FetchOutcome> {
        let outcome = fetch_block_and_witness(FetchRequest {
            rpc_url: &opts.rpc_url,
            block_number: opts.block_number,
            data_dir: opts.data_dir,
            save_all_responses: opts.save_all_responses,
            build_eth_test: opts.build_eth_test,
        })
        .await?;
        Ok(outcome)
    }

    pub fn execute_block(&self, opts: ExecuteOptions) -> Result<ExecutionLog> {
        let input_path = self.resolve_input_path(
            opts.block_number,
            opts.file_name,
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
        let stdin = if opts.is_test {
            build_stdin_from_eth_tests(&input_path)?
        } else {
            build_stdin_from_unified_rlp(&input_path)?
        };

        let client = ProverClient::from_env();

        let (mut output, report) = client.execute(SILK_ST_ELF, &stdin).run().unwrap();

        let gas_used = output.read::<u64>();
        let cycle_count = report.total_instruction_count();
        info!(
            "execution complete, block={} gas_used={}, cycle_count={}",
            opts.block_number, gas_used, cycle_count
        );

        let log = ExecutionLog {
            block_number: opts.block_number,
            gas_used,
            cycle_count,
            input_path: input_path.clone(),
        };
        self.persist_execution_logs(&opts.data_dir, &log)?;
        Ok(log)
    }

    pub async fn prove_block(&self, opts: &ProveOptions) -> Result<ProvingLog> {
        let input_path = self.resolve_input_path(
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

        let stdin = if opts.is_test {
            build_stdin_from_eth_tests(&input_path)?
        } else {
            build_stdin_from_unified_rlp(&input_path)?
        };

        let cfg = bincode::config::standard();
        let pk: SP1ProvingKey = {
            let mut r = BufReader::new(File::open(&opts.pk_path)?);
            bincode::serde::decode_from_std_read(&mut r, cfg)?
        };

        // Lock the client for exclusive proving access
        let client = self.client.lock().await;

        let cycle_count = 0;

        let start = Instant::now();
        let mut proof = match opts.proof_type.as_str() {
            "core" => client.prove(&pk, &stdin).run(),
            "groth16" => client.prove(&pk, &stdin).groth16().run(),
            "plonk" => client.prove(&pk, &stdin).plonk().run(),
            _ => client.prove(&pk, &stdin).compressed().run(),
        }
        .unwrap();
        let proving_millis = start.elapsed().as_millis() as u64;
        let gas_used = proof.public_values.read::<u64>();

        // Drop the client lock here so other operations can proceed
        drop(client);

        let proof_path = self.write_proof(&opts, &proof)?;
        let log = ProvingLog {
            block_number: opts.block_number,
            gas_used,
            proof_path: proof_path.clone(),
            proof_type: opts.proof_type.clone(),
            proving_millis,
            message: String::from("Success"),
        };
        self.persist_proving_logs(&opts.data_dir, &log)?;
        Ok(log)
    }

    // Static version of prove_block that takes client as parameter for concurrent use
    async fn prove_block_with_client(
        opts: &ProveOptions,
        client_arc: Arc<Mutex<EnvProver>>,
    ) -> Result<ProvingLog> {
        let input_path = if let Some(file_name) = &opts.file_name {
            file_name.clone()
        } else {
            let file_path = if opts.is_test {
                format!("ethTests{}.json", opts.block_number)
            } else {
                format!("unifiedBlockAndStateRlp{}.bin", opts.block_number)
            };
            opts.data_dir
                .join(opts.block_number.to_string())
                .join(file_path)
        };

        if !input_path.exists() {
            bail!(
                "input file for block {} not found at {}",
                opts.block_number,
                input_path.display()
            );
        }

        let stdin = if opts.is_test {
            build_stdin_from_eth_tests(&input_path)?
        } else {
            build_stdin_from_unified_rlp(&input_path)?
        };

        let cfg = bincode::config::standard();
        let pk: SP1ProvingKey = {
            let mut r = BufReader::new(File::open(&opts.pk_path)?);
            bincode::serde::decode_from_std_read(&mut r, cfg)?
        };

        // Lock the client for exclusive proving access
        let client = client_arc.lock().await;
        // Write proof to file
        let proof_path = opts
            .data_dir
            .join(opts.block_number.to_string())
            .join(format!("proof{}.bin", opts.block_number));

        if let Some(parent) = proof_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let start = Instant::now();
        let proof_result = match opts.proof_type.as_str() {
            "core" => client.prove(&pk, &stdin).run(),
            "groth16" => client.prove(&pk, &stdin).groth16().run(),
            "plonk" => client.prove(&pk, &stdin).plonk().run(),
            _ => client.prove(&pk, &stdin).compressed().run(),
        };

        let proving_millis = start.elapsed().as_millis() as u64;

        // Drop the client lock here so other operations can proceed
        drop(client);

        match proof_result {
            Ok(mut proof) => {
                let gas_used = proof.public_values.read::<u64>();

                let cfg = bincode::config::standard();
                let mut fp = BufWriter::new(File::create(&proof_path)?);
                bincode::serde::encode_into_std_write(&proof, &mut fp, cfg)?;

                let log = ProvingLog {
                    block_number: opts.block_number,
                    gas_used,
                    proof_path: proof_path.clone(),
                    proof_type: opts.proof_type.clone(),
                    proving_millis,
                    message: String::from("Success"),
                };

                // Write log to file
                Self::persist_proving_logs_static(&opts.data_dir, &log)?;
                Ok(log)
            }
            Err(err) => {
                println!(
                    "[{}] Error trying to prove block {}: {}",
                    Self::format_timestamp(),
                    opts.block_number,
                    err
                );

                let log = ProvingLog {
                    block_number: opts.block_number,
                    gas_used: 0,
                    proof_path: proof_path.clone(),
                    proof_type: opts.proof_type.clone(),
                    proving_millis,
                    message: err.to_string(),
                };

                Self::persist_proving_logs_static(&opts.data_dir, &log)?;
                bail!("Proving failed: {}", err)
            }
        }
    }

    pub async fn verify_proof(&self, opts: VerifyOptions) -> Result<()> {
        let cfg = bincode::config::standard();
        let mut proof: SP1ProofWithPublicValues = {
            let mut r = BufReader::new(File::open(&opts.proof_path)?);
            bincode::serde::decode_from_std_read(&mut r, cfg)?
        };

        let vk: SP1VerifyingKey = {
            let mut r = BufReader::new(File::open(&opts.vk_path)?);
            bincode::serde::decode_from_std_read(&mut r, cfg)?
        };

        let client = self.client.lock().await;
        client
            .verify(&proof, &vk)
            .wrap_err("failed to verify proof")?;

        let gas_used = proof.public_values.read::<u64>();
        info!("verification complete, gas_used={}", gas_used);
        Ok(())
    }

    pub async fn run_service(&self, service: ServiceConfig) -> Result<()> {
        info!("starting service mode");
        let url = Url::parse(&service.rpc_url)?;
        let provider = ProviderBuilder::new().connect_http(url);

        let mut next_block = if let Some(start) = service.start_block {
            start
        } else {
            match Self::get_block_number_with_retry(&provider, 3).await {
                Ok(block_num) => block_num.saturating_add(1),
                Err(e) => {
                    error!("Failed to get initial block number after retries: {}", e);
                    return Err(e);
                }
            }
        };

        info!("Service starting from block: {}", next_block);

        loop {
            match Self::get_block_number_with_retry(&provider, 3).await {
                Ok(latest) => {
                    // Collect blocks to process
                    let blocks_to_process: Vec<u64> = (next_block..=latest).collect();

                    // Process all blocks concurrently
                    let data_dir = self.config.data_dir.clone();
                    let client_arc = self.client.clone(); // Clone the Arc<Mutex<EnvProver>>
                    let tasks: Vec<_> = blocks_to_process
                        .into_iter()
                        .map(|block_num| {
                            let service_clone = service.clone();
                            let data_dir_clone = data_dir.clone();
                            let client_clone = client_arc.clone();
                            tokio::spawn(async move {
                                if let Err(err) = Self::process_block_static(
                                    block_num,
                                    &service_clone,
                                    &data_dir_clone,
                                    client_clone,
                                )
                                .await
                                {
                                    error!(%block_num, error = %err, "failed to process block");
                                }
                            })
                        })
                        .collect();

                    if !tasks.is_empty() {
                        // Wait for all spawned tasks to complete
                        for task in tasks {
                            let _ = task.await;
                        }
                        next_block = latest + 1;
                    }
                }
                Err(err) => {
                    error!(error = %err, "Failed to get latest block number after retries, will retry in 30 seconds");
                    sleep(Duration::from_secs(30)).await;
                    continue;
                }
            }

            sleep(Duration::from_secs(6)).await;
        }
    }

    // Helper method to get block number with retry logic
    async fn get_block_number_with_retry<P>(provider: &P, max_retries: u32) -> Result<u64>
    where
        P: Provider,
    {
        let mut attempts = 0;

        loop {
            match provider.get_block_number().await {
                Ok(block_number) => return Ok(block_number),
                Err(err) => {
                    attempts += 1;
                    if attempts >= max_retries {
                        return Err(err.into());
                    }

                    let delay = Duration::from_secs(2_u64.pow(attempts.min(5))); // Exponential backoff, max 32 seconds
                    warn!(
                        attempt = attempts,
                        max_retries = max_retries,
                        delay_secs = delay.as_secs(),
                        error = %err,
                        "Failed to get block number, retrying..."
                    );
                    sleep(delay).await;
                }
            }
        }
    }

    // Process block using shared client for proper synchronization
    async fn process_block_static(
        block_number: u64,
        service: &ServiceConfig,
        data_dir: &PathBuf,
        client: Arc<Mutex<EnvProver>>,
    ) -> Result<()> {
        println!(
            "[{}] Received block number from RPC {}",
            Self::format_timestamp(),
            block_number
        );
        let should_prove = matches_interval(service.prove_every, block_number);
        let should_execute = matches_interval(service.execute_every, block_number) && !should_prove;
        let should_post = matches_interval(service.post_every, block_number);

        let should_anything = should_prove || should_execute || service.save_all_responses;
        if !should_anything {
            println!(
                "[{}] Nothing to do for block {}",
                Self::format_timestamp(),
                block_number
            );
            return Ok(());
        }

        let outcome = fetch_block_and_witness(FetchRequest {
            rpc_url: &service.rpc_url,
            block_number: Some(block_number),
            data_dir: data_dir.clone(),
            save_all_responses: service.save_all_responses,
            build_eth_test: false,
        })
        .await?;
        let unified_path = outcome.unified_rlp_path.clone();

        if should_execute {
            println!(
                "[{}] Executing only block {}",
                Self::format_timestamp(),
                block_number
            );
            if let Err(err) = Self::execute_block_static(block_number, &unified_path, data_dir) {
                error!(%block_number, error = %err, "execution failed");
            }
        }

        let mut proof_log: Option<ProvingLog> = None;
        if should_prove {
            println!(
                "[{}] Proving block {}",
                Self::format_timestamp(),
                block_number
            );
            let pk_path = match service.proving_key_path.clone() {
                Some(path) => path,
                None => {
                    warn!(%block_number, "skipping proving because no pk_path provided");
                    return Ok(());
                }
            };
            let prove_opts = ProveOptions {
                block_number,
                file_name: Some(unified_path.clone()),
                is_test: false,
                data_dir: data_dir.clone(),
                pk_path: pk_path.clone(),
                proof_path: None, // Will be generated by prove_block method
                proof_type: service.proof_type.clone(),
            };

            match Self::prove_block_with_client(&prove_opts, client.clone()).await {
                Ok(log) => {
                    proof_log = Some(log);
                }
                Err(err) => {
                    error!(%block_number, error = %err, "proving failed");
                }
            }
        }

        if should_post {
            if let Some(_log) = proof_log.as_ref() {
                // TODO: Handle ethproofs posting in static context
                warn!(%block_number, "ethproofs posting not implemented in concurrent mode");
            }
        }

        Ok(())
    }

    fn execute_block_static(
        block_number: u64,
        input_path: &PathBuf,
        data_dir: &PathBuf,
    ) -> Result<ExecutionLog> {
        if !input_path.exists() {
            bail!(
                "input file for block {} not found at {}",
                block_number,
                input_path.display()
            );
        }

        let stdin = build_stdin_from_unified_rlp(input_path)?;
        let client = ProverClient::from_env();
        let (mut output, report) = client.execute(SILK_ST_ELF, &stdin).run().unwrap();

        let gas_used = output.read::<u64>();
        let cycle_count = report.total_instruction_count();
        info!(
            "execution complete, block={} gas_used={}, cycle_count={}",
            block_number, gas_used, cycle_count
        );

        let log = ExecutionLog {
            block_number,
            gas_used,
            cycle_count,
            input_path: input_path.clone(),
        };
        Self::persist_execution_logs_static(data_dir, &log)?;
        Ok(log)
    }

    fn persist_execution_logs_static(data_dir: &Path, log: &ExecutionLog) -> Result<()> {
        let log_file: PathBuf = data_dir.join("executionLogs.log");
        let mut text_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)?;
        let timestamp = Self::format_timestamp();
        writeln!(
            &mut text_file,
            "[{}] block {} executed, gas_used={}, cycles={}, input={}",
            timestamp,
            log.block_number,
            log.gas_used,
            log.cycle_count,
            log.input_path.display()
        )?;
        Ok(())
    }

    fn persist_proving_logs_static(data_dir: &Path, log: &ProvingLog) -> Result<()> {
        let log_file: PathBuf = data_dir.join("provingLogs.log");
        let mut text_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)?;
        let timestamp = Self::format_timestamp();
        writeln!(
            &mut text_file,
            "[{}] block {} proved, gas_used={}, proof_path={}, proof_type={}, proving_ms={}",
            timestamp,
            log.block_number,
            log.gas_used,
            log.proof_path.display(),
            log.proof_type,
            log.proving_millis
        )?;
        Ok(())
    }

    fn resolve_input_path(
        &self,
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
        let dir = data_dir.join("blocks/".to_owned() + &block_number.to_string());
        let file_name = if is_test {
            format!("ethTests{}.json", block_number)
        } else {
            format!("unifiedBlockAndStateRlp{}.bin", block_number)
        };
        Ok(dir.join(file_name))
    }

    fn write_proof(
        &self,
        opts: &ProveOptions,
        proof: &SP1ProofWithPublicValues,
    ) -> Result<PathBuf> {
        let cfg = bincode::config::standard();
        let target_path = if let Some(path) = &opts.proof_path {
            path.clone()
        } else {
            opts.data_dir
                .join(opts.block_number.to_string())
                .join(format!("proof{}.bin", opts.block_number))
        };
        if let Some(parent) = target_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut fp = BufWriter::new(File::create(&target_path)?);
        bincode::serde::encode_into_std_write(proof, &mut fp, cfg)?;
        Ok(target_path)
    }

    fn persist_execution_logs(&self, data_dir: &Path, log: &ExecutionLog) -> Result<()> {
        let log_file: PathBuf = data_dir.join("executionLogs.log");
        let mut text_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)?;
        let timestamp = Self::format_timestamp();
        writeln!(
            &mut text_file,
            "[{}] block {} executed, gas_used={}, cycles={}, input={}",
            timestamp,
            log.block_number,
            log.gas_used,
            log.cycle_count,
            log.input_path.display()
        )?;
        Ok(())
    }

    fn persist_proving_logs(&self, data_dir: &Path, log: &ProvingLog) -> Result<()> {
        let log_file: PathBuf = data_dir.join("provingLogs.log");
        let mut text_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)?;
        let timestamp = Self::format_timestamp();
        writeln!(
            &mut text_file,
            "[{}] block {} proved, gas_used={}, proof_path={}, proof_type={}, proving_ms={}",
            timestamp,
            log.block_number,
            log.gas_used,
            log.proof_path.display(),
            log.proof_type,
            log.proving_millis
        )?;
        Ok(())
    }
}

fn matches_interval(interval: Option<u64>, block_number: u64) -> bool {
    match interval {
        Some(0) => false,
        Some(n) => block_number % n == 0,
        None => false,
    }
}
