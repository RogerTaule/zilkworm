
// use std::{
//     collections::{BTreeMap, HashMap},
//     fs,
//     io::{BufReader, BufWriter},
//     str::FromStr,
// };

// use alloy_primitives::{hex, keccak256, Address, Bytes, B256, U256};
// use alloy_rlp::Decodable;
// use alloy_rpc_types_debug::ExecutionWitness;
// use anyhow::{anyhow, Context, Result};
// use clap::Parser;
// use alloy_consensus::Account;
// use rsp_mpt::EthereumState;
// use serde::Serialize;
// use serde_json::{Map, Value};
// use sp1_sdk::{
//     include_elf, ProverClient, SP1ProofWithPublicValues, SP1ProvingKey, SP1Stdin, SP1VerifyingKey,
// };


// fn convert_to_eth_tests_json(raw: &str) -> Result<String> {
//     let value: Value = serde_json::from_str(raw)?;
//     let converted = convert_program_input(value)?;
//     Ok(serde_json::to_string(&converted)?)
// }


// fn convert_program_input(input: Value) -> Result<Value> {
//     let block = input
//         .get("block")
//         .cloned()
//         .ok_or_else(|| anyhow!("missing `block` field in input JSON"))?;
//     let parent_block = input
//         .get("parentBlock")
//         .cloned()
//         .ok_or_else(|| anyhow!("missing `parentBlock` field in input JSON"))?;
//     let witness_value = input
//         .get("execution_witness")
//         .cloned()
//         .ok_or_else(|| anyhow!("missing `execution_witness` field in input JSON"))?;
//     let network_value = input.get("network").cloned();

//     let witness: ExecutionWitness =
//         serde_json::from_value(witness_value).context("failed to decode execution witness")?;

//     let state_root_hex = parent_block
//         .get("blockHeader")
//         .and_then(|header| header.get("stateRoot"))
//         .and_then(Value::as_str)
//         .ok_or_else(|| anyhow!("missing `parentBlock.blockHeader.stateRoot`"))?;

//     let pre_state_root = B256::from_str(state_root_hex)
//         .with_context(|| format!("invalid state root: {state_root_hex}"))?;

//     let state = EthereumState::from_execution_witness(&witness, pre_state_root);
//     let pre = build_pre_state(&state, &witness)?;

//     let mut output = Map::new();
//     output.insert("blocks".to_string(), Value::Array(vec![block.clone()]));

//     if let Some(header) = parent_block.get("blockHeader") {
//         output.insert("genesisBlockHeader".to_string(), header.clone());
//     }
//     if let Some(genesis_rlp) = parent_block.get("rlp") {
//         output.insert("genesisRLP".to_string(), genesis_rlp.clone());
//     }
//     if let Some(last_hash) = block.get("blockHeader").and_then(|header| header.get("hash")).cloned()
//     {
//         output.insert("lastblockhash".to_string(), last_hash);
//     }
//     if let Some(network) = network_value {
//         output.insert("network".to_string(), network);
//     }

//     // Empty postState - just for sanity a.t.m.
//     output.insert("postState".to_string(), Value::Object(Map::new()));
//     output.insert("pre".to_string(), serde_json::to_value(pre)?);

//     Ok(Value::Object(output))
// }


// #[derive(Debug, Serialize)]
// struct AccountStateJson {
//     balance: String,
//     code: String,
//     nonce: String,
//     #[serde(skip_serializing_if = "BTreeMap::is_empty")]
//     storage: BTreeMap<String, String>,
// }

// fn build_pre_state(
//     state: &EthereumState,
//     witness: &ExecutionWitness,
// ) -> Result<BTreeMap<String, AccountStateJson>> {
//     let mut address_by_hash: HashMap<B256, Address> = HashMap::new();
//     let mut slot_by_hash: HashMap<B256, B256> = HashMap::new();

//     for key in &witness.keys {
//         let bytes = key.as_ref();
//         match bytes.len() {
//             20 => {
//                 let address = Address::from_slice(bytes);
//                 address_by_hash.insert(keccak256(address), address);
//             }
//             32 => {
//                 let slot = B256::from_slice(bytes);
//                 slot_by_hash.insert(keccak256(slot), slot);
//             }
//             _ => {}
//         }
//     }

//     let mut code_by_hash: HashMap<B256, Bytes> = HashMap::new();
//     for code in &witness.codes {
//         code_by_hash.insert(keccak256(code), code.clone());
//     }

//     let mut leaves = Vec::new();
//     state.state_trie.for_each_leaves(|key, value| {
//         leaves.push((B256::from_slice(key), value.to_vec()));
//     });

//     let empty_code_hash = keccak256(&[]);
//     let mut pre = BTreeMap::new();

//     for (hashed_address, encoded_account) in leaves {
//         let address = address_by_hash.get(&hashed_address).ok_or_else(|| {
//             anyhow!(
//                 "missing account address preimage for hash {}",
//                 to_prefixed_hex(hashed_address.as_slice())
//             )
//         })?;

//         let mut slice: &[u8] = &encoded_account;
//         let account = Account::decode(&mut slice)
//             .with_context(|| format!("failed to decode account for {address:#x}"))?;

//         let code = if account.code_hash == empty_code_hash {
//             "0x".to_string()
//         } else {
//             let code_bytes = code_by_hash
//                 .get(&account.code_hash)
//                 .ok_or_else(|| anyhow!("missing bytecode preimage for account {address:#x}"))?;
//             to_prefixed_hex(code_bytes.as_ref())
//         };

//         let mut storage = BTreeMap::new();
//         if let Some(storage_trie) = state.storage_tries.get(&hashed_address) {
//             let mut storage_leaves = Vec::new();
//             storage_trie.for_each_leaves(|slot_key, value| {
//                 storage_leaves.push((B256::from_slice(slot_key), value.to_vec()));
//             });
//             storage_leaves.sort_by_key(|(slot, _)| *slot);

//             for (hashed_slot, encoded_value) in storage_leaves {
//                 let slot = slot_by_hash.get(&hashed_slot).ok_or_else(|| {
//                     anyhow!(
//                         "missing storage slot preimage for account {address:#x} and slot hash {}",
//                         to_prefixed_hex(hashed_slot.as_slice())
//                     )
//                 })?;
//                 let mut slice: &[u8] = &encoded_value;
//                 let value = U256::decode(&mut slice).with_context(|| {
//                     format!(
//                         "failed to decode storage value for account {address:#x} slot {}",
//                         to_prefixed_hex(slot.as_slice())
//                     )
//                 })?;
//                 if value.is_zero() {
//                     continue;
//                 }
//                 storage.insert(to_prefixed_hex(slot.as_slice()), encode_u256(value));
//             }
//         }

//         let entry = AccountStateJson {
//             balance: encode_u256(account.balance),
//             code,
//             nonce: encode_u256(U256::from(account.nonce)),
//             storage,
//         };

//         pre.insert(format!("{address:#x}"), entry);
//     }

//     Ok(pre)
// }

// fn encode_u256(value: U256) -> String {
//     let bytes = value.to_be_bytes::<32>();
//     to_prefixed_hex(&bytes)
// }

// fn to_prefixed_hex(bytes: &[u8]) -> String {
//     let hex_str = hex::encode(bytes);
//     let trimmed = hex_str.trim_start_matches('0');
//     let mut body = if trimmed.is_empty() {
//         String::from("00")
//     } else {
//         let mut owned = trimmed.to_string();
//         if owned.len() % 2 != 0 {
//             owned.insert(0, '0');
//         }
//         owned
//     };
//     if body.len() == 1 {
//         body.insert(0, '0');
//     }
//     format!("0x{body}")
// }
