#!/usr/bin/env python3
"""
Comprehensive script to find gas usage divergences between stdout and trace data.
Get the trace using eth_getBlockReceipts
Get the stdout in the stdout.yml
"""

import json
import re
import sys

def read_stdout_data(filename):
    """Read the stdout data from the untitled file with logs content."""
    try:
        with open(filename, 'r') as f:
            content = f.read()
        
        # Split by transaction entries
        tx_entries = re.split(r'Txn Gas used:', content)[1:]  # Skip first empty part
        
        result = []
        for entry in tx_entries:
            lines = entry.split('\n')
            if not lines:
                continue
                
            # Parse first line: hash logs.size:X cumulative_gas_used:Y
            first_line = lines[0].strip()
            if len(first_line) < 66:
                continue
                
            tx_hash = first_line[:64]  # 64 hex chars without 0x
            normalized_hash = "0x" + tx_hash.lower()
            remaining = first_line[64:].strip()
            
            # Extract logs.size and cumulative gas
            logs_size_match = re.search(r'logs\.size:(\d+)', remaining)
            logs_size = int(logs_size_match.group(1)) if logs_size_match else 0
            
            cum_gas_match = re.search(r'cumulative_gas_used:(\d+)', remaining)
            cumulative_gas = int(cum_gas_match.group(1)) if cum_gas_match else 0
            
            # Parse logs content
            logs_data = []
            if logs_size > 0:
                # Find "Logs:" line
                logs_start_idx = -1
                for i, line in enumerate(lines):
                    if line.strip() == 'Logs:':
                        logs_start_idx = i
                        break
                
                if logs_start_idx != -1:
                    # Collect all lines from after "Logs:" until next transaction or end
                    logs_lines = []
                    for i in range(logs_start_idx + 1, len(lines)):
                        line = lines[i]
                        # Stop if we hit another transaction header
                        if line.strip().startswith('Txn Gas used:'):
                            break
                        logs_lines.append(line)
                    
                    # Join and parse logs JSON
                    if logs_lines:
                        logs_json_str = '\n'.join(logs_lines).strip()
                        
                        # Clean up malformed JSON
                        # Fix trailing commas before ] or }
                        logs_json_str = re.sub(r',\s*]', ']', logs_json_str, flags=re.MULTILINE)
                        logs_json_str = re.sub(r',\s*}', '}', logs_json_str, flags=re.MULTILINE)
                        # Fix double 0x prefixes in addresses
                        logs_json_str = re.sub(r'"0x0x([a-fA-F0-9]+)"', r'"0x\1"', logs_json_str)
                        # Fix trailing commas in topics arrays
                        logs_json_str = re.sub(r',\s*]\s*,\s*"data"', '], "data"', logs_json_str, flags=re.MULTILINE)
                        
                        try:
                            parsed_logs = json.loads(logs_json_str)
                            if isinstance(parsed_logs, list):
                                # Normalize log data
                                for log in parsed_logs:
                                    normalized_log = {
                                        'address': log.get('address', '').lower().strip(),
                                        'topics': [topic.strip() for topic in log.get('topics', [])],
                                        'data': log.get('data', '').strip()
                                    }
                                    logs_data.append(normalized_log)
                        except json.JSONDecodeError as e:
                            print(f"Error parsing logs JSON for {normalized_hash}: {e}")
                            print(f"Raw logs: {logs_json_str[:300]}...")
                            logs_data = []
            
            result.append((normalized_hash, int(cumulative_gas), int(logs_size), logs_data))
        
        return result
    except Exception as e:
        print(f"Error reading stdout data: {e}")
        return []

def read_trace_data(filename):
    """Read the eth_getBlockReceipts data from JSON file."""
    try:
        with open(filename, 'r') as f:
            data = json.load(f)
        # eth_getBlockReceipts returns receipts in result field
        return data.get('result', [])
    except Exception as e:
        print(f"Error reading trace data: {e}")
        return []

def calculate_individual_gas(cumulative_data):
    """Convert cumulative gas to individual transaction gas usage."""
    individual_gas = {}
    prev_cumulative = 0
    
    for i, (tx_hash, cumulative, logs_size, logs_data) in enumerate(cumulative_data):
        individual = cumulative - prev_cumulative
        individual_gas[tx_hash] = {
            'individual': individual,
            'cumulative': cumulative,
            'logs_size': logs_size,
            'logs_data': logs_data,
            'index': i,
            'tx_hash': tx_hash
        }
        prev_cumulative = cumulative
        
    return individual_gas

def extract_trace_gas(traces):
    """Extract gas usage and logs data from eth_getBlockReceipts results."""
    trace_gas = {}
    tx_order = []
    seen_txs = set()
    
    # For eth_getBlockReceipts, each receipt has direct gasUsed field
    for receipt in traces:
        if not isinstance(receipt, dict):
            continue
            
        if 'transactionHash' in receipt and 'gasUsed' in receipt:
            tx_hash = receipt['transactionHash'].lower()
            
            # Track transaction order (only add once per transaction)
            if tx_hash not in seen_txs:
                tx_order.append(tx_hash)
                seen_txs.add(tx_hash)
                
                # Extract gas used from receipt (already individual, not cumulative)
                gas_used = receipt['gasUsed']
                if isinstance(gas_used, str) and gas_used.startswith('0x'):
                    gas_used = int(gas_used, 16)
                elif isinstance(gas_used, str):
                    gas_used = int(gas_used)
                
                # Extract and normalize logs data
                logs_data = receipt.get('logs', [])
                logs_count = len(logs_data)
                
                # Normalize log data - ensure addresses are lowercase
                normalized_logs = []
                for log in logs_data:
                    normalized_log = {
                        'address': log.get('address', '').lower(),
                        'topics': log.get('topics', []),
                        'data': log.get('data', '')
                    }
                    normalized_logs.append(normalized_log)
                
                trace_gas[tx_hash] = {
                    'gas_used': gas_used,
                    'logs_count': logs_count,
                    'logs_data': normalized_logs
                }

    return trace_gas, tx_order

def find_first_divergence(stdout_file, trace_file, threshold=100):
    """Find the first transaction where gas usage diverges significantly."""
    
    print("=== Gas Divergence Analysis ===")
    print(f"Threshold for divergence: {threshold}")
    print()
    
    # Load data
    stdout_data = read_stdout_data(stdout_file)
    traces = read_trace_data(trace_file)
    
    if not stdout_data:
        print("Error: No stdout data found")
        return
    if not traces:
        print("Error: No trace data found")
        return
        
    print(f"Loaded {len(stdout_data)} transactions from stdout")
    print(f"Loaded {len(traces)} traces from trace file")
    
    # Process data
    individual_gas = calculate_individual_gas(stdout_data)
    trace_gas, trace_order = extract_trace_gas(traces)
    
    print(f"Parsed {len(individual_gas)} individual gas entries")
    print(f"Parsed {len(trace_gas)} trace gas entries")
    print(f"Transaction order from traces: {len(trace_order)} unique transactions")
    print()
    
    def compare_logs(stdout_logs, trace_logs):
        """Compare log contents deeply."""
        if len(stdout_logs) != len(trace_logs):
            return False, f"Count mismatch: {len(stdout_logs)} vs {len(trace_logs)}"
        
        for i, (stdout_log, trace_log) in enumerate(zip(stdout_logs, trace_logs)):
            if stdout_log.get('address', '') != trace_log.get('address', ''):
                return False, f"Log {i} address mismatch"
            if stdout_log.get('topics', []) != trace_log.get('topics', []):
                return False, f"Log {i} topics mismatch"
            if stdout_log.get('data', '') != trace_log.get('data', ''):
                return False, f"Log {i} data mismatch"
        
        return True, "Logs match"
    
    # Find divergences
    print("=== TRANSACTION-BY-TRANSACTION ANALYSIS ===")
    print(f"{'Index':<6} {'TX Hash':<66} {'Stdout Gas':<12} {'Trace Gas':<12} {'Gas Diff':<10} {'Stdout Logs':<12} {'Trace Logs':<12} {'Log Diff':<10} {'Status'}")
    print("=" * 180)
    
    first_divergence = None
    perfect_matches = 0
    total_compared = 0
    gas_divergences = 0
    log_divergences = 0
    log_content_mismatches = 0
    log_mismatch_details = []
    
    # Use stdout order for comparison
    for tx_hash, data in individual_gas.items():
        stdout_gas = data['individual']
        stdout_logs = data['logs_size']
        stdout_logs_data = data['logs_data']
        
        trace_data = trace_gas.get(tx_hash, {'gas_used': 0, 'logs_count': 0, 'logs_data': []})
        trace_gas_val = trace_data['gas_used']
        trace_logs_val = trace_data['logs_count']
        trace_logs_data = trace_data['logs_data']
        
        gas_diff = abs(stdout_gas - trace_gas_val)
        log_diff = abs(stdout_logs - trace_logs_val)
        
        # Deep compare logs content
        logs_match, log_mismatch_reason = compare_logs(stdout_logs_data, trace_logs_data)
        
        status_parts = []
        if gas_diff == 0 and log_diff == 0 and logs_match:
            status = "MATCH"
        else:
            if gas_diff > 0:
                status_parts.append(f"GAS:{gas_diff}")
                if gas_diff > threshold:
                    gas_divergences += 1
            if log_diff > 0:
                status_parts.append(f"LOG_COUNT:{log_diff}")
                log_divergences += 1
            if not logs_match:
                status_parts.append("LOGS_MISMATCH")
                log_content_mismatches += 1
                log_mismatch_details.append({
                    'index': data['index'],
                    'tx_hash': tx_hash,
                    'reason': log_mismatch_reason,
                    'stdout_logs': stdout_logs_data,
                    'trace_logs': trace_logs_data
                })
            status = " ".join(status_parts) if status_parts else "MATCH"
            
        print(f"{data['index']:<6} {tx_hash:<66} {stdout_gas:<12} {trace_gas_val:<12} {gas_diff:<10} {stdout_logs:<12} {trace_logs_val:<12} {log_diff:<10} {status}")
        
        if (gas_diff > threshold or log_diff > 0 or not logs_match) and first_divergence is None:
            first_divergence = {
                'index': data['index'],
                'tx_hash': tx_hash,
                'stdout_gas': stdout_gas,
                'trace_gas': trace_gas_val,
                'gas_difference': gas_diff,
                'stdout_logs': stdout_logs,
                'trace_logs': trace_logs_val,
                'log_difference': log_diff,
                'logs_match': logs_match,
                'log_mismatch_reason': log_mismatch_reason,
                'cumulative': data['cumulative']
            }
            
        if gas_diff == 0 and log_diff == 0 and logs_match:
            perfect_matches += 1
        total_compared += 1
    
    print()
    print("=== SUMMARY ===")
    print(f"Total transactions compared: {total_compared}")
    print(f"Perfect matches (gas + logs count + logs content): {perfect_matches}")
    print(f"Transactions with gas differences > {threshold}: {gas_divergences}")
    print(f"Transactions with log count differences: {log_divergences}")
    print(f"Transactions with log content mismatches: {log_content_mismatches}")
    
    if log_mismatch_details:
        print()
        print("=== LOG CONTENT MISMATCHES ===")
        for mismatch in log_mismatch_details[:5]:  # Show first 5 mismatches
            print(f"Transaction {mismatch['index']}: {mismatch['tx_hash']}")
            print(f"  Reason: {mismatch['reason']}")
            print(f"  Stdout logs count: {len(mismatch['stdout_logs'])}")
            print(f"  Trace logs count: {len(mismatch['trace_logs'])}")
            
            # Show detailed log comparison
            for i, (stdout_log, trace_log) in enumerate(zip(mismatch['stdout_logs'], mismatch['trace_logs'])):
                if (stdout_log.get('address', '') != trace_log.get('address', '') or 
                    stdout_log.get('topics', []) != trace_log.get('topics', []) or
                    stdout_log.get('data', '') != trace_log.get('data', '')):
                    print(f"    Log {i} differences:")
                    if stdout_log.get('address', '') != trace_log.get('address', ''):
                        print(f"      Address: stdout='{stdout_log.get('address', '')}' trace='{trace_log.get('address', '')}'")
                    if stdout_log.get('topics', []) != trace_log.get('topics', []):
                        print(f"      Topics: stdout={len(stdout_log.get('topics', []))} topics, trace={len(trace_log.get('topics', []))} topics")
                    if stdout_log.get('data', '') != trace_log.get('data', ''):
                        print(f"      Data: stdout='{stdout_log.get('data', '')[:50]}...' trace='{trace_log.get('data', '')[:50]}...'")
            print()
    
    if first_divergence:
        print()
        print("=== FIRST SIGNIFICANT DIVERGENCE ===")
        print(f"Transaction Index: {first_divergence['index']}")
        print(f"Transaction Hash: {first_divergence['tx_hash']}")
        print(f"Stdout Individual Gas: {first_divergence['stdout_gas']:,}")
        print(f"Trace Individual Gas: {first_divergence['trace_gas']:,}")
        print(f"Gas Difference: {first_divergence['gas_difference']:,}")
        print(f"Stdout Logs Count: {first_divergence['stdout_logs']}")
        print(f"Trace Logs Count: {first_divergence['trace_logs']}")
        print(f"Log Count Difference: {first_divergence['log_difference']}")
        print(f"Logs Content Match: {first_divergence['logs_match']}")
        if not first_divergence['logs_match']:
            print(f"Log Mismatch Reason: {first_divergence['log_mismatch_reason']}")
        print(f"Cumulative Gas (stdout): {first_divergence['cumulative']:,}")
        
        # Show context around the divergence
        print()
        print("=== CONTEXT AROUND DIVERGENCE ===")
        div_index = first_divergence['index']
        start_idx = max(0, div_index - 2)
        end_idx = min(len(stdout_data), div_index + 3)
        
        for i in range(start_idx, end_idx):
            if i < len(stdout_data):
                tx_hash, cumulative, logs_size, _ = stdout_data[i]
                tx_hash = tx_hash.lower()
                individual = individual_gas[tx_hash]['individual']
                stdout_logs_ctx = individual_gas[tx_hash]['logs_size']
                trace_data_ctx = trace_gas.get(tx_hash, {'gas_used': 0, 'logs_count': 0})
                trace_val = trace_data_ctx['gas_used']
                trace_logs_ctx = trace_data_ctx['logs_count']
                marker = " --> DIVERGENCE" if i == div_index else ""
                print(f"  {i}: {tx_hash} | Gas - Stdout: {individual:,} Trace: {trace_val:,} | Logs - Stdout: {stdout_logs_ctx} Trace: {trace_logs_ctx} | Cum: {cumulative:,}{marker}")
    else:
        print()
        print("No significant divergences found!")
    
    # Check for missing transactions
    stdout_hashes = set(individual_gas.keys())
    trace_hashes = set(trace_gas.keys())
    
    missing_in_trace = stdout_hashes - trace_hashes
    missing_in_stdout = trace_hashes - stdout_hashes
    
    if missing_in_trace or missing_in_stdout:
        print()
        print("=== MISSING TRANSACTIONS ===")
        if missing_in_trace:
            print(f"In stdout but not in traces: {len(missing_in_trace)}")
            for tx in list(missing_in_trace)[:3]:
                print(f"  {tx}")
        if missing_in_stdout:
            print(f"In traces but not in stdout: {len(missing_in_stdout)}")
            for tx in list(missing_in_stdout)[:3]:
                print(f"  {tx}")

def main():
    # Default files
    stdout_file = "./stdout.yml"
    trace_file = "./trace.json"
    
    if len(sys.argv) >= 2:
        stdout_file = sys.argv[1]
    if len(sys.argv) >= 3:
        trace_file = sys.argv[2]
        
    print(f"Using stdout file: {stdout_file}")
    print(f"Using trace file: {trace_file}")
    print()
    
    find_first_divergence(stdout_file, trace_file)

if __name__ == "__main__":
    main()