use sp1_sdk::SP1Stdin;
use std::{
    collections::{BTreeMap, HashMap},
    fs,
    io::BufWriter,
    path::PathBuf,
};

// Import alloy types (updated for 1.0)
use alloy_consensus::{BlockHeader, Transaction};

use alloy_primitives::{keccak256, Address, Bytes, B256, U256};
use alloy_provider::{ext::DebugApi, Provider, ProviderBuilder};
use alloy_rlp::{Decodable, Encodable};
use alloy_rpc_types::{Block as RpcBlock, BlockTransactions, Transaction as RPCTransaction};
use alloy_rpc_types_debug::ExecutionWitness;
use alloy_trie::{TrieAccount, EMPTY_ROOT_HASH, KECCAK_EMPTY};
use eyre::{bail, eyre, Context, Result};
use serde::Serialize;
use url::Url;
use rsp_mpt::EthereumState;

use crate::rlp_methods::*;
// Import the types from our types module
use crate::types::{
    BlockchainTestCase, EthTestAccessListItem, EthTestAccount, EthTestAuthorization,
    EthTestTransaction, SealEngine, TestBlock, TestHeader,
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
    // let prev_block_rlp_path = block_dir.join(format!("blockRlp{}.json", block_number - 1));
    let tests_path = block_dir.join(format!("ethTests{}.json", block_number));
    let unified_rlp_path = block_dir.join(format!("inputRlpUnified{}.json", block_number));
    let unified_block_rlp_only_path =
        block_dir.join(format!("unifiedBlockAndStateRlp{}.json", block_number));

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

    // Generate previous block RLP with header only
    prev_block_rlp = block_to_header_only_rlp(&prev_block)?;

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

    if tests_path.exists() {
        println!(
            "Tests Path exists at {}, nothing to do",
            tests_path.display()
        );
    } else {
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
    }

    // if unified_rlp_path.exists() {
    //     println!(
    //         "Unified rlp file for block {} exists at {}",
    //         block_number,
    //         unified_rlp_path.display()
    //     );
    // } else {
        let unified_rlp_map = build_unified_rlp_map(
            block_number,
            &current_block,
            &current_block_rlp,
            &prev_block,
            &prev_block_rlp,
            &execution_witness,
        )?;
        write_json(&unified_rlp_path, &unified_rlp_map)?;
        println!(
            "Saved Unified RLP file for block {} to {}",
            block_number,
            unified_rlp_path.display()
        );
        // Write the bytes into file
        if let Some(unified_rlp_bytes) = unified_rlp_map.get("unifiedBlockAndStateRlp") {
            fs::write(unified_block_rlp_only_path, unified_rlp_bytes)?;
        }
    // }

    Ok(())
}

pub fn build_stdin_from_eth_tests(path: &PathBuf) -> Result<SP1Stdin> {
    let mut stdin = SP1Stdin::new();

    // is_test
    stdin.write(&true);
    // Read the eth tests JSON
    let raw = fs::read_to_string(path)?;
    let value: serde_json::Value = serde_json::from_str(&raw)?;
    let minified = serde_json::to_string(&value)?;

    stdin.write_slice(minified.as_bytes());

    println!("Loaded eth tests: {} bytes", minified.len());

    Ok(stdin)
}

pub fn build_stdin_from_unified_rlp(path: &PathBuf) -> Result<SP1Stdin> {
    let mut stdin = SP1Stdin::new();

    // is_test
    stdin.write(&false);

    // Read the Unified RLP bytes JSON
    let raw = fs::read(path)?;
    stdin.write_slice(&raw.as_ref());

    println!("Loaded Unified RLP: {} bytes", raw.len());

    Ok(stdin)
}

pub fn write_json<T: ?Sized + Serialize>(path: &PathBuf, value: &T) -> Result<()> {
    let file = fs::File::create(path)?;
    let writer = BufWriter::new(file);
    serde_json::to_writer_pretty(writer, value)?;
    Ok(())
}

// Build eth tests case - same as fetcher.rs but updated for alloy 1.0
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

    // Create a list of the three RLP items as byte arrays
    let items = vec![
        prev_block_rlp.as_ref(),
        block_rlp.as_ref(),
        pre_state_rlp.as_ref(),
    ];

    // Encode the list
    let unified_rlp = alloy_rlp::encode(&items);

    let mut input_map = BTreeMap::<String, Bytes>::new();
    input_map.insert("genesisRlp".to_string(), prev_block_rlp.clone());
    input_map.insert("blockRlp".to_string(), block_rlp.clone());
    input_map.insert("preState".to_string(), pre_state_rlp.clone());
    input_map.insert(
        "unifiedBlockAndStateRlp".to_string(),
        Bytes::from(unified_rlp),
    );

    Ok(input_map)
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


// /// Encode a single account to RLP (as it would appear in the state trie)
// fn encode_account_to_rlp(account: &EthTestAccount) -> Result<Vec<u8>> {
//     // Calculate code hash if code exists
//     let code_hash = if account.code.is_empty() {
//         KECCAK_EMPTY
//     } else {
//         keccak256(&account.code)
//     };

//     // Calculate storage root
//     // For simplicity, we'll use empty root if no storage
//     // In production, you'd build a storage trie and get its root
//     let storage_root = if account.storage.is_empty() {
//         EMPTY_ROOT_HASH
//     } else {
//         // Build storage trie and get root
//         calculate_storage_root(&account.storage)?
//     };

//     // Create TrieAccount structure
//     let trie_account = TrieAccount {
//         nonce: account.nonce.to::<u64>(),
//         balance: account.balance,
//         storage_root,
//         code_hash,
//     };

//     // Encode the TrieAccount
//     let mut output = Vec::new();
//     trie_account.encode(&mut output);

//     Ok(output)
// }

/// Calculate storage root from storage mapping
fn calculate_storage_root(storage: &BTreeMap<U256, U256>) -> Result<B256> {
    use alloy_trie::{HashBuilder, Nibbles};

    // Create a new hash builder for the storage trie
    let mut hash_builder = HashBuilder::default();

    // Add all storage entries
    for (slot, value) in storage.iter() {
        // Skip zero values as they're not stored in the trie
        if value.is_zero() {
            continue;
        }

        // Hash the storage slot key
        let hashed_slot = keccak256(slot.to_be_bytes::<32>());

        // Convert to nibbles for trie insertion
        let key_nibbles = Nibbles::unpack(hashed_slot);

        // Encode the value
        let mut value_rlp = Vec::new();
        value.encode(&mut value_rlp);

        // Add to hash builder
        hash_builder.add_leaf(key_nibbles, &value_rlp);
    }

    // Get the root hash
    Ok(hash_builder.root())
}

/// Alternative: Encode pre_state as it appears in ethereum tests JSON
/// This encodes in a format suitable for test consumption
pub fn encode_pre_state_for_tests(pre_state: &BTreeMap<Address, EthTestAccount>) -> Result<Bytes> {
    // For test format, we might want a different encoding
    // This would be a list of [address, nonce, balance, storage_rlp, code]
    let mut test_entries = Vec::new();

    for (address, account) in pre_state.iter() {
        // Create a list: [address, nonce, balance, storage, code]
        let mut fields = Vec::new();

        // Address
        let mut addr_bytes = Vec::new();
        address.encode(&mut addr_bytes);
        fields.push(addr_bytes);

        // Nonce
        let mut nonce_bytes = Vec::new();
        account.nonce.encode(&mut nonce_bytes);
        fields.push(nonce_bytes);

        // Balance
        let mut balance_bytes = Vec::new();
        account.balance.encode(&mut balance_bytes);
        fields.push(balance_bytes);

        // Storage (as a list of key-value pairs)
        let mut storage_bytes = Vec::new();
        if !account.storage.is_empty() {
            let storage_pairs: Vec<Vec<u8>> = account
                .storage
                .iter()
                .map(|(k, v)| {
                    let mut pair = Vec::new();
                    k.encode(&mut pair);
                    v.encode(&mut pair);
                    pair
                })
                .collect();
            storage_bytes = alloy_rlp::encode(&storage_pairs);
        } else {
            // Empty list
            storage_bytes.push(0xc0);
        }
        fields.push(storage_bytes);

        // Code
        let mut code_bytes = Vec::new();
        account.code.encode(&mut code_bytes);
        fields.push(code_bytes);

        // Encode the entry as a list
        let entry = alloy_rlp::encode(&fields);
        test_entries.push(entry);
    }

    // Encode all entries as a list
    let output = alloy_rlp::encode(&test_entries);

    Ok(Bytes::from(output))
}
