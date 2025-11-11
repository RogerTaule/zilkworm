#!/bin/bash

# Script to run z6m_prover in parallel for multiple block numbers
# Usage: ./run_parallel_prover.sh [--jobs N] <block_number1> <block_number2> ...
# Example: ./run_parallel_prover.sh --jobs 8 23745000 23749200 23753400

set -e

# Default configuration
MAX_JOBS=12
DATA_DIR="prover/temp"
# DATA_DIR="/data"
# PROVER_BIN="docker run -v "$PWD/prover/temp:/data:rw" somnergy/z6m_prover"
PROVER_BIN="target/release/z6m_prover"
LOG_DIR="prover/temp/logs"

# Parse arguments
if [ "$1" == "--jobs" ] || [ "$1" == "-j" ]; then
    MAX_JOBS=$2
    shift 2
fi

BLOCKS=("$@")

if [ ${#BLOCKS[@]} -eq 0 ]; then
    echo "Usage: $0 [--jobs N] <block_number1> <block_number2> ..."
    echo ""
    echo "Options:"
    echo "  --jobs, -j N    Number of parallel jobs (default: 4)"
    echo ""
    echo "Example:"
    echo "  $0 --jobs 8 23745000 23749200 23753400 23759700"
    exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR"

echo "Running ${#BLOCKS[@]} blocks with $MAX_JOBS parallel jobs..."
echo "Prover binary: $PROVER_BIN"
echo "Data directory: $DATA_DIR"
echo "Logs directory: $LOG_DIR"
echo ""

# Function to run a single block
run_block() {
    local block=$1
    local log_file="$LOG_DIR/block_${block}.log"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting block $block" | tee -a "$log_file"
    
    if $PROVER_BIN execute --block-number "$block" --data-dir "$DATA_DIR" >> "$log_file" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Completed block $block" | tee -a "$log_file"
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ Failed block $block (exit code: $?)" | tee -a "$log_file"
        return 1
    fi
}

export -f run_block
export PROVER_BIN
export DATA_DIR
export LOG_DIR

# Track progress
TOTAL=${#BLOCKS[@]}
COMPLETED=0
FAILED=0

# Summary log
SUMMARY_LOG="$LOG_DIR/summary_$(date '+%Y%m%d_%H%M%S').log"
echo "Execution started at $(date)" > "$SUMMARY_LOG"
echo "Total blocks: $TOTAL" >> "$SUMMARY_LOG"
echo "Parallel jobs: $MAX_JOBS" >> "$SUMMARY_LOG"
echo "Blocks: ${BLOCKS[*]}" >> "$SUMMARY_LOG"
echo "" >> "$SUMMARY_LOG"

# Run blocks in parallel using background jobs
for block in "${BLOCKS[@]}"; do
    # Wait if we've hit the max concurrent jobs
    while [ $(jobs -r | wc -l) -ge $MAX_JOBS ]; do
        sleep 1
    done
    
    # Run block in background
    run_block "$block" &
done

# Wait for all background jobs to complete
echo ""
echo "Waiting for all jobs to complete..."
wait

# Generate summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"

for block in "${BLOCKS[@]}"; do
    log_file="$LOG_DIR/block_${block}.log"
    if grep -q "✓ Completed" "$log_file" 2>/dev/null; then
        ((COMPLETED++))
        echo "✓ Block $block - SUCCESS" >> "$SUMMARY_LOG"
    else
        ((FAILED++))
        echo "✗ Block $block - FAILED" >> "$SUMMARY_LOG"
    fi
done

echo "Total blocks: $TOTAL"
echo "Completed: $COMPLETED"
echo "Failed: $FAILED"
echo ""
echo "Execution completed at $(date)" >> "$SUMMARY_LOG"
echo "Completed: $COMPLETED" >> "$SUMMARY_LOG"
echo "Failed: $FAILED" >> "$SUMMARY_LOG"

echo ""
echo "Logs saved to: $LOG_DIR"
echo "Summary: $SUMMARY_LOG"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
