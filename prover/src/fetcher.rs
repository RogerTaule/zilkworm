use crate::rlp_methods::{block_to_header_only_rlp, build_pre_state_rlp};
use crate::types::{
    BlockchainTestCase, EthTestAccessListItem, EthTestAccount, EthTestAuthorization,
    EthTestTransaction, SealEngine, TestBlock, TestHeader,
};
use alloy_consensus::transaction::SignerRecoverable;
use alloy_consensus::{BlockHeader, Transaction};
use alloy_primitives::{keccak256, Address, Bytes, B256, U256};
use alloy_provider::{ext::DebugApi, Provider, ProviderBuilder};
use alloy_rlp::{Decodable, Encodable};
use alloy_rpc_types::{Block as RpcBlock, BlockTransactions, Transaction as RPCTransaction};
use alloy_rpc_types_debug::ExecutionWitness;
use alloy_trie::{TrieAccount, KECCAK_EMPTY};
use eyre::{bail, eyre, Context, Result};
use rsp_mpt::EthereumState;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::io::BufWriter;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::time::sleep;
use tracing::{debug, warn};
use url::Url;

pub struct FetchRequest<'a> {
    pub rpc_url: &'a str,
    pub block_number: Option<u64>,
    pub data_dir: PathBuf,
    pub save_all_responses: bool,
    pub build_eth_test: bool,
}

pub struct FetchOutcome {
    pub block_number: u64,
    pub block_directory: PathBuf,
    pub unified_rlp_path: PathBuf,
}

pub async fn fetch_block_and_witness(request: FetchRequest<'_>) -> Result<FetchOutcome> {
    let url = Url::parse(request.rpc_url)?;
    let provider = ProviderBuilder::new().connect_http(url);

    let mut block_number = if let Some(num) = request.block_number {
        num
    } else {
        get_block_number_with_retry(&provider, 3).await?
    };

    if block_number == 0 {
        block_number = get_block_number_with_retry(&provider, 3).await?;
    }
    if block_number == 0 {
        bail!("cannot fetch block 0 without a parent");
    }

    let blocks_dir: PathBuf = request.data_dir.join("blocks");
    let block_dir: PathBuf = blocks_dir.join(block_number.to_string());
    std::fs::create_dir_all(&block_dir)?;

    let block_path = block_dir.join(format!("block{}.json", block_number));
    let block_rlp_path = block_dir.join(format!("blockRlp{}.json", block_number));
    let prev_number = block_number
        .checked_sub(1)
        .ok_or_else(|| eyre!("block {} has no parent", block_number))?;
    let prev_block_path = block_dir.join(format!("block{}.json", prev_number));
    let witness_path = block_dir.join(format!("executionWitness{}.json", block_number));
    let tests_path = block_dir.join(format!("ethTests{}.json", block_number));
    // let unified_map_path = block_dir.join(format!("inputRlpUnified{}.json", block_number));
    let unified_rlp_only_path =
        block_dir.join(format!("unifiedBlockAndStateRlp{}.bin", block_number));

    let current_block: RpcBlock = if block_path.exists() {
        let block_json = fs::read_to_string(&block_path)?;
        serde_json::from_str(&block_json)?
    } else {
        let fetched = get_block_by_number_with_retry(&provider, block_number, 3)
            .await?
            .ok_or_else(|| eyre!("block {} not found", block_number))?;
        if request.save_all_responses {
            write_json(&block_path, &fetched)?;
        }
        fetched
    };

    let current_block_rlp: Bytes = if block_rlp_path.exists() {
        let block_rlp_json = fs::read_to_string(&block_rlp_path)?;
        serde_json::from_str(&block_rlp_json)?
    } else {
        let rlp = debug_get_raw_block_with_retry(&provider, block_number, 3).await?;
        if request.save_all_responses {
            write_json(&block_rlp_path, &rlp)?;
        }
        rlp
    };

    let prev_block: RpcBlock = if prev_block_path.exists() {
        let block_json = fs::read_to_string(&prev_block_path)?;
        serde_json::from_str(&block_json)?
    } else {
        let fetched = get_block_by_number_with_retry(&provider, prev_number, 3)
            .await?
            .ok_or_else(|| eyre!("block {} not found", prev_number))?;
        if request.save_all_responses {
            write_json(&prev_block_path, &fetched)?;
        }
        fetched
    };

    let prev_block_rlp = block_to_header_only_rlp(&prev_block)?;

    let execution_witness: ExecutionWitness = if witness_path.exists() {
        let witness_json = fs::read_to_string(&witness_path)?;
        serde_json::from_str(&witness_json)?
    } else {
        let witness = debug_execution_witness_with_retry(&provider, block_number, 3)
            .await
            .wrap_err("failed to fetch execution witness after retries")?;
        if request.save_all_responses {
            write_json(&witness_path, &witness)?;
        }
        witness
    };

    if request.save_all_responses && !tests_path.exists() && request.build_eth_test {
        let eth_tests = build_eth_tests_case(
            block_number,
            &current_block,
            &current_block_rlp,
            &prev_block,
            &prev_block_rlp,
            &execution_witness,
        )?;
        write_json(&tests_path, &eth_tests)?;
    }

    let unified_rlp_map = build_unified_rlp_map(
        block_number,
        &current_block,
        &current_block_rlp,
        &prev_block,
        &prev_block_rlp,
        &execution_witness,
    )?;

    // if request.save_all_responses {
    //     write_json(&unified_map_path, &unified_rlp_map)?;
    // }

    if let Some(unified_rlp_bytes) = unified_rlp_map.get("unifiedBlockAndStateRlp") {
        fs::write(&unified_rlp_only_path, unified_rlp_bytes)?;
    } else {
        bail!("missing unifiedBlockAndStateRlp entry");
    }

    debug!(
        %block_number,
        "fetched block data and wrote unified rlp to {:?}",
        unified_rlp_only_path
    );

    Ok(FetchOutcome {
        block_number,
        block_directory: block_dir,
        unified_rlp_path: unified_rlp_only_path,
    })
}

// Helper functions for network retry logic
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

async fn get_block_by_number_with_retry<P>(
    provider: &P,
    block_number: u64,
    max_retries: u32,
) -> Result<Option<RpcBlock>>
where
    P: Provider,
{
    let mut attempts = 0;

    loop {
        match provider.get_block_by_number(block_number.into()).await {
            Ok(block) => return Ok(block),
            Err(err) => {
                attempts += 1;
                if attempts >= max_retries {
                    return Err(err.into());
                }

                let delay = Duration::from_secs(2_u64.pow(attempts.min(5)));
                warn!(
                    attempt = attempts,
                    max_retries = max_retries,
                    delay_secs = delay.as_secs(),
                    block_number = block_number,
                    error = %err,
                    "Failed to get block by number, retrying..."
                );
                sleep(delay).await;
            }
        }
    }
}

async fn debug_get_raw_block_with_retry<P>(
    provider: &P,
    block_number: u64,
    max_retries: u32,
) -> Result<Bytes>
where
    P: Provider + DebugApi,
{
    let mut attempts = 0;

    loop {
        match provider.debug_get_raw_block(block_number.into()).await {
            Ok(rlp) => return Ok(rlp),
            Err(err) => {
                attempts += 1;
                if attempts >= max_retries {
                    return Err(err.into());
                }

                let delay = Duration::from_secs(2_u64.pow(attempts.min(5)));
                warn!(
                    attempt = attempts,
                    max_retries = max_retries,
                    delay_secs = delay.as_secs(),
                    block_number = block_number,
                    error = %err,
                    "Failed to get raw block, retrying..."
                );
                sleep(delay).await;
            }
        }
    }
}

async fn debug_execution_witness_with_retry<P>(
    provider: &P,
    block_number: u64,
    max_retries: u32,
) -> Result<ExecutionWitness>
where
    P: Provider + DebugApi,
{
    let mut attempts = 0;

    loop {
        match provider.debug_execution_witness(block_number.into()).await {
            Ok(witness) => return Ok(witness),
            Err(err) => {
                attempts += 1;
                if attempts >= max_retries {
                    return Err(err.into());
                }

                let delay = Duration::from_secs(2_u64.pow(attempts.min(5)));
                warn!(
                    attempt = attempts,
                    max_retries = max_retries,
                    delay_secs = delay.as_secs(),
                    block_number = block_number,
                    error = %err,
                    "Failed to get execution witness, retrying..."
                );
                sleep(delay).await;
            }
        }
    }
}

pub fn write_json<T: ?Sized + Serialize>(path: &Path, value: &T) -> Result<()> {
    let file = fs::File::create(path)?;
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, value)?;
    Ok(())
}

pub fn build_stdin_from_eth_tests(path: &Path) -> Result<sp1_sdk::SP1Stdin> {
    use sp1_sdk::SP1Stdin;
    let mut stdin = SP1Stdin::new();
    stdin.write(&true);
    let raw = fs::read_to_string(path)?;
    let value: serde_json::Value = serde_json::from_str(&raw)?;
    let minified = serde_json::to_string(&value)?;
    stdin.write_slice(minified.as_bytes());
    Ok(stdin)
}

pub fn build_stdin_from_unified_rlp(path: &Path) -> Result<sp1_sdk::SP1Stdin> {
    use sp1_sdk::SP1Stdin;
    let mut stdin = SP1Stdin::new();
    stdin.write(&false);
    let raw = fs::read(path)?;
    stdin.write_slice(&raw);
    Ok(stdin)
}

fn build_unified_rlp_map(
    _block_number: u64,
    _current_block: &RpcBlock,
    block_rlp: &Bytes,
    previous_block: &RpcBlock,
    prev_block_rlp: &Bytes,
    witness: &ExecutionWitness,
) -> Result<BTreeMap<String, Bytes>> {
    let pre_state_root = previous_block.header.state_root;
    let state = EthereumState::from_execution_witness(witness, pre_state_root);

    let code_map: HashMap<B256, Bytes> = witness
        .codes
        .iter()
        .cloned()
        .map(|code| (keccak256(&code), code))
        .collect();

    let preimage_map: HashMap<B256, Bytes> = witness
        .keys
        .iter()
        .cloned()
        .map(|preimage| (keccak256(&preimage), preimage))
        .collect();

    let pre_state_rlp = build_pre_state_rlp(&state, &code_map, &preimage_map)?;

    let items = vec![
        prev_block_rlp.as_ref(),
        block_rlp.as_ref(),
        pre_state_rlp.as_ref(),
    ];
    let unified_rlp = alloy_rlp::encode(&items);

    let mut input_map = BTreeMap::<String, Bytes>::new();
    // input_map.insert("genesisRlp".to_string(), prev_block_rlp.clone());
    // input_map.insert("blockRlp".to_string(), block_rlp.clone());
    // input_map.insert("preState".to_string(), pre_state_rlp.clone());
    input_map.insert(
        "unifiedBlockAndStateRlp".to_string(),
        Bytes::from(unified_rlp),
    );

    Ok(input_map)
}

fn build_eth_tests_case(
    block_number: u64,
    current_block: &RpcBlock,
    block_rlp: &Bytes,
    previous_block: &RpcBlock,
    prev_block_rlp: &Bytes,
    witness: &ExecutionWitness,
) -> Result<BTreeMap<String, BlockchainTestCase>> {
    let pre_state_root = previous_block.header.state_root;
    let state = EthereumState::from_execution_witness(witness, pre_state_root);

    let code_map: HashMap<B256, Bytes> = witness
        .codes
        .iter()
        .cloned()
        .map(|code| (keccak256(&code), code))
        .collect();

    let preimage_map: HashMap<B256, Bytes> = witness
        .keys
        .iter()
        .cloned()
        .map(|preimage| (keccak256(&preimage), preimage))
        .collect();

    let pre = build_pre_state(&state, &code_map, &preimage_map);

    let transactions = match &current_block.transactions {
        BlockTransactions::Full(txs) => {
            let mut converted = Vec::with_capacity(txs.len());
            for tx in txs.iter() {
                converted.push(convert_transaction(tx)?);
            }
            Some(converted)
        }
        _ => None,
    };

    let block_case = TestBlock {
        block_header: Some(convert_header(&current_block.header)),
        rlp: block_rlp.clone(),
        expect_exception: None,
        transactions,
        uncle_headers: None,
        transaction_sequence: None,
        withdrawals: current_block.withdrawals.clone(),
    };

    let mut cases = BTreeMap::new();
    cases.insert(
        format!("block_{block_number}"),
        BlockchainTestCase {
            genesis_block_header: convert_header(&previous_block.header),
            genesis_rlp: Some(prev_block_rlp.clone()),
            blocks: vec![block_case],
            post_state: None,
            pre,
            lastblockhash: current_block.header.hash,
            network: "Cancun".to_string(),
            seal_engine: SealEngine::NoProof,
        },
    );

    Ok(cases)
}

fn build_pre_state(
    state: &EthereumState,
    code_map: &HashMap<B256, Bytes>,
    preimage_map: &HashMap<B256, Bytes>,
) -> BTreeMap<Address, EthTestAccount> {
    let mut accounts = BTreeMap::new();

    state.state_trie.for_each_leaves(|key, value| {
        let hashed_address = B256::from_slice(key);
        if let Some(address_bytes) = preimage_map.get(&hashed_address) {
            if address_bytes.len() != Address::len_bytes() {
                return;
            }
            let address = Address::from_slice(address_bytes.as_ref());
            let mut bytes = value;
            if let Ok(account) = TrieAccount::decode(&mut bytes) {
                let code = if account.code_hash == KECCAK_EMPTY {
                    Bytes::default()
                } else {
                    code_map
                        .get(&account.code_hash)
                        .cloned()
                        .unwrap_or_default()
                };

                let mut storage = BTreeMap::new();
                if let Some(storage_trie) = state.storage_tries.get(&hashed_address) {
                    storage_trie.for_each_leaves(|slot_key, slot_value| {
                        let hashed_slot = B256::from_slice(slot_key);
                        if let Some(slot_preimage) = preimage_map.get(&hashed_slot) {
                            if slot_preimage.len() == 32 {
                                let slot = U256::from_be_slice(slot_preimage.as_ref());
                                let mut slot_bytes = slot_value;
                                if let Ok(value) = U256::decode(&mut slot_bytes) {
                                    if !value.is_zero() {
                                        storage.insert(slot, value);
                                    }
                                }
                            }
                        }
                    });
                }

                accounts.insert(
                    address,
                    EthTestAccount {
                        balance: account.balance,
                        code,
                        nonce: U256::from(account.nonce),
                        storage,
                    },
                );
            }
        }
    });

    accounts
}

fn convert_transaction(tx: &RPCTransaction) -> Result<EthTestTransaction> {
    let from = tx.inner.recover_signer()?;
    let hash = Some(*tx.inner.hash());
    let ty = match tx.inner.tx_type() {
        alloy_consensus::TxType::Legacy => 0,
        alloy_consensus::TxType::Eip2930 => 1,
        alloy_consensus::TxType::Eip1559 => 2,
        alloy_consensus::TxType::Eip4844 => 3,
        alloy_consensus::TxType::Eip7702 => 4,
    };
    let transaction_type = if ty == 0 { None } else { Some(U256::from(ty)) };
    let gas_price = tx.gas_price().map(U256::from);
    let max_fee_per_gas = Some(U256::from(tx.max_fee_per_gas()));
    let max_priority_fee_per_gas = tx.max_priority_fee_per_gas().map(U256::from);
    let max_fee_per_blob_gas = tx.max_fee_per_blob_gas().map(U256::from);

    let access_list: Option<Vec<EthTestAccessListItem>> = tx.access_list().as_ref().map(|list| {
        list.0
            .iter()
            .map(|item| EthTestAccessListItem {
                address: item.address,
                storage_keys: item.storage_keys.clone(),
            })
            .collect()
    });

    let authorization_list: Option<Vec<EthTestAuthorization>> =
        tx.authorization_list().as_ref().map(|list| {
            list.iter()
                .map(|auth| EthTestAuthorization {
                    chain_id: U256::from(auth.chain_id),
                    address: auth.address,
                    nonce: U256::from(auth.nonce),
                    y_parity: U256::from(if auth.y_parity() != 0 { 1u64 } else { 0u64 }),
                    r: auth.r(),
                    s: auth.s(),
                })
                .collect()
        });

    let blob_versioned_hashes = tx.blob_versioned_hashes().map(|hashes| hashes.to_vec());

    let (r, s, v) = {
        let sig = tx.inner.signature();
        (sig.r(), sig.s(), U256::from(sig.v()))
    };

    Ok(EthTestTransaction {
        transaction_type,
        data: tx.input().clone(),
        gas_limit: U256::from(tx.gas_limit()),
        gas_price,
        nonce: U256::from(tx.nonce()),
        r,
        s,
        v,
        value: tx.value(),
        chain_id: tx.chain_id().map(U256::from),
        access_list,
        max_fee_per_gas,
        max_priority_fee_per_gas,
        max_fee_per_blob_gas,
        blob_versioned_hashes,
        authorization_list,
        to: tx.to(),
        from: Some(from),
        hash,
    })
}

fn convert_header(header: &alloy_rpc_types::Header) -> TestHeader {
    TestHeader {
        bloom: header.logs_bloom,
        coinbase: header.beneficiary,
        difficulty: header.difficulty,
        extra_data: header.extra_data.clone(),
        gas_limit: U256::from(header.gas_limit),
        gas_used: U256::from(header.gas_used),
        hash: header.hash,
        mix_hash: header.mix_hash().unwrap_or_default(),
        nonce: header.nonce,
        number: U256::from(header.number),
        parent_hash: header.parent_hash,
        receipt_trie: header.receipts_root,
        state_root: header.state_root,
        timestamp: U256::from(header.timestamp),
        transactions_trie: header.transactions_root,
        uncle_hash: header.ommers_hash,
        base_fee_per_gas: header.base_fee_per_gas.map(U256::from),
        withdrawals_root: header.withdrawals_root,
        blob_gas_used: header.blob_gas_used.map(U256::from),
        excess_blob_gas: header.excess_blob_gas.map(U256::from),
        parent_beacon_block_root: header.parent_beacon_block_root,
        requests_hash: header.requests_hash,
        target_blobs_per_block: None,
    }
}
