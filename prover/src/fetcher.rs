use clap::Parser;
use sp1_sdk::{
    include_elf, ProverClient, SP1ProofWithPublicValues, SP1ProvingKey, SP1Stdin, SP1VerifyingKey,
};
use std::{
    any::{self, Any},
    collections::{BTreeMap, HashMap},
    fs,
    io::{BufReader, BufWriter},
    path::PathBuf,
};

// Import alloy types (updated for 1.0)
use alloy_consensus::{Block, BlockHeader, Transaction, TxEnvelope};
use alloy_eips::eip4895::Withdrawals;
use alloy_network::{Ethereum, Network};
use alloy_primitives::{keccak256, Address, Bloom, Bytes, B256, B64, U256};
use alloy_provider::{ext::DebugApi, Provider, ProviderBuilder};
use alloy_rlp::Decodable;
use alloy_rpc_types::{Block as RpcBlock, BlockTransactions, Transaction as RPCTransaction};
use alloy_rpc_types_debug::ExecutionWitness;
use alloy_transport::Transport;
use alloy_transport_http::Http;
use alloy_trie::{TrieAccount, KECCAK_EMPTY};
use eyre::{bail, eyre, Context, Result};
use reqwest::Client;
use serde::Serialize;
use url::Url;

use rsp_mpt::EthereumState;

// Import the types from our types module
use crate::types::{
    BlockchainTestCase, EthTestAccessListItem, EthTestAccount, EthTestAuthorization,
    EthTestTransaction, SealEngine, TestBlock, TestHeader, TransactionSequence,
};

pub async fn fetch_block_and_witness(
    rpc_url: String,
    mut block_number: u64,
    output: PathBuf,
) -> Result<()> {
    let url = Url::parse(&rpc_url)?;
    let provider = ProviderBuilder::new().connect_http(url);

    if block_number == 0 {
        // Fetch the latest
        block_number = provider.get_block_number().await?;
    }

    // Create output directory
    let block_dir: PathBuf = output.join(format!("{}", block_number));
    let witness_path = block_dir.join(format!("executionWitness{}.json", block_number));
    let block_path = block_dir.join(format!("block{}.json", block_number));
    let block_rlp_path = block_dir.join(format!("blockRlp{}.json", block_number));
    let prev_block_path = block_dir.join(format!("block{}.json", block_number - 1));
    let prev_block_rlp_path = block_dir.join(format!("blockRlp{}.json", block_number - 1));
    let tests_path = block_dir.join(format!("ethTests{}.json", block_number));

    let current_block;
    let current_block_rlp;
    let prev_block;
    let prev_block_rlp;
    let execution_witness;

    // Download or load current block
    if block_path.exists() {
        println!(
            "Loading existing block {} from {}",
            block_number,
            block_path.display()
        );
        let block_json = fs::read_to_string(&block_path)?;
        current_block = serde_json::from_str(&block_json)?;

        // For RLP, try to load from file, otherwise fetch it
        if block_rlp_path.exists() {
            let block_rlp_json = fs::read_to_string(&block_rlp_path)?;
            current_block_rlp = serde_json::from_str(&block_rlp_json)?;
        } else {
            current_block_rlp = provider.debug_get_raw_block(block_number.into()).await?;
            write_json(&block_rlp_path, &current_block_rlp)?;
        }
    } else {
        println!("Fetching block {}...", block_number);
        std::fs::create_dir_all(&block_dir)?;

        // Fetch current block with full transactions
        current_block = provider
            .get_block_by_number(block_number.into())
            .await?
            .ok_or_else(|| eyre!("block {} not found", block_number))?;

        // Fetch current block RLP
        current_block_rlp = provider.debug_get_raw_block(block_number.into()).await?;

        // Write to disk
        write_json(&block_path, &current_block)?;
        write_json(&block_rlp_path, &current_block_rlp)?;
        println!("Written block and RLP for block_number {}...", block_number);
    }

    // Download or load previous block
    if prev_block_path.exists() {
        println!(
            "Loading existing block {} from {}",
            block_number - 1,
            prev_block_path.display()
        );
        let block_json = fs::read_to_string(&prev_block_path)?;
        prev_block = serde_json::from_str(&block_json)?;
    } else {
        println!("Fetching block {}...", block_number - 1);
        std::fs::create_dir_all(&block_dir)?;

        // Fetch current block with full transactions
        prev_block = provider
            .get_block_by_number((block_number - 1).into())
            .await?
            .ok_or_else(|| eyre!("block {} not found", block_number))?;

        write_json(&prev_block_path, &prev_block)?;
        println!(
            "Written block and RLP for block_number {}...",
            block_number - 1
        );
    }
    if prev_block_rlp_path.exists() {
        let prev_block_rlp_json = fs::read_to_string(&prev_block_rlp_path)?;
        prev_block_rlp = serde_json::from_str(&prev_block_rlp_json)?;
    } else {
        prev_block_rlp = provider.debug_get_raw_block(block_number.into()).await?;
        write_json(&prev_block_rlp_path, &current_block_rlp)?;
    }

    if witness_path.exists() {
        println!(
            "Loading existing witness for block {} from {}",
            block_number,
            witness_path.display()
        );
        let witness_json = fs::read_to_string(&witness_path)?;
        execution_witness = serde_json::from_str(&witness_json)?;
    } else {
        println!("Fetching execution witness...");

        // Fetch execution witness
        execution_witness = provider
            // .debug_execution_witness(alloy_eips::BlockNumberOrTag::Latest)
            .debug_execution_witness(block_number.into())
            .await
            .wrap_err("failed to fetch execution witness")?;

        // Save witness
        write_json(&witness_path, &execution_witness)?;
    }
    // Build and save eth tests
    let eth_tests = build_eth_tests_case(
        block_number,
        &current_block,
        &current_block_rlp,
        &prev_block,
        &prev_block_rlp,
        &execution_witness,
    )?;

    write_json(&tests_path, &eth_tests)?;

    println!(
        "Saved eth-tests JSON for block {}, to location {}",
        block_number,
        tests_path.display()
    );

    Ok(())
}

pub fn build_stdin_from_eth_tests(path: &PathBuf) -> Result<SP1Stdin> {
    let mut stdin = SP1Stdin::new();

    // Read the eth tests JSON
    let raw = fs::read_to_string(path)?;
    let value: serde_json::Value = serde_json::from_str(&raw)?;
    let minified = serde_json::to_string(&value)?;

    stdin.write_slice(minified.as_bytes());

    println!("Loaded eth tests: {} bytes", minified.len());

    Ok(stdin)
}

pub fn write_json<T: ?Sized + Serialize>(path: &PathBuf, value: &T) -> Result<()> {
    let file = fs::File::create(path)?;
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, value)?;
    Ok(())
}

// Build eth tests case - same as fetcher.rs but updated for alloy 1.0
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

    // let block_rlp = block_to_rlp(current_block)?;
    let genesis_rlp = prev_block_rlp;

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

fn block_to_rlp(block: &RpcBlock) -> Result<Bytes> {
    // In alloy 1.0, we need to handle this slightly differently
    let BlockTransactions::Full(ref txs) = block.transactions else {
        bail!(
            "block {} is missing full transactions for RLP encoding",
            block.header.number
        );
    };

    // Convert transactions to TxEnvelope
    let tx_envelopes: Vec<TxEnvelope> = txs
        .iter()
        .map(|tx| TxEnvelope::try_from(tx.clone()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| eyre!("Failed to convert transaction: {}", e))?;

    // Create a consensus block - this part might need adjustment based on your exact needs
    // You might need to construct the block manually
    Ok(Bytes::from(alloy_rlp::encode(&tx_envelopes)))
}

// Add this import at the top of the file
use alloy_consensus::transaction::SignerRecoverable;

fn convert_transaction(tx: &RPCTransaction) -> Result<EthTestTransaction> {
    // Fix: Use the correct method and add required trait
    let from = tx.inner.recover_signer()?;
    // Fix: Use tx_hash() instead of hash()
    let hash = Some(*tx.inner.hash());

    // Fix: TxKind doesn't have unwrap_or, need to match on it
    let ty = match tx.inner.tx_type() {
        alloy_consensus::TxType::Legacy => 0,
        alloy_consensus::TxType::Eip2930 => 1,
        alloy_consensus::TxType::Eip1559 => 2,
        alloy_consensus::TxType::Eip4844 => 3,
        alloy_consensus::TxType::Eip7702 => 4,
    };
    let transaction_type = if ty == 0 { None } else { Some(U256::from(ty)) };

    // Fix: Handle Option<u128> properly
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

    // Fix: Handle Option<&[B256]> properly
    let blob_versioned_hashes = tx.blob_versioned_hashes().map(|hashes| hashes.to_vec());

    // Fix: Match on the dereferenced inner transaction and handle Recovered type
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
