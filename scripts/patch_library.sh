#!/usr/bin/env bash
# Patch EBREAK instructions in all object files within a static library (.a file)
# Usage: ./patch_library.sh libstdc++.a

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <library.a>"
    exit 1
fi

LIBRARY="$1"

if [ ! -f "$LIBRARY" ]; then
    echo "Error: $LIBRARY not found"
    exit 1
fi

# Make backup
BACKUP="${LIBRARY}.bak"
if [ ! -f "$BACKUP" ]; then
    echo "Creating backup: $BACKUP"
    cp "$LIBRARY" "$BACKUP"
fi

# Create temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Extracting archive..."
cd "$TMPDIR"
ar x "$OLDPWD/$LIBRARY"

# Count total EBREAKs before patching
TOTAL_BEFORE=0
for obj in *.o; do
    if [ -f "$obj" ]; then
        COUNT=$(riscv-none-elf-objdump -d "$obj" 2>/dev/null | grep -c "ebreak" || true)
        TOTAL_BEFORE=$((TOTAL_BEFORE + COUNT))
    fi
done
echo "Found $TOTAL_BEFORE EBREAK instructions in archive"

# Patch each object file
PATCHED=0
for obj in *.o; do
    if [ ! -f "$obj" ]; then
        continue
    fi
    
    # Check if this object has any executable sections with EBREAK
    if riscv-none-elf-objdump -d "$obj" 2>/dev/null | grep -q "ebreak"; then
        echo "Patching $obj..."
        # Use python to patch the binary (replace 73 00 10 00 with 13 00 00 00)
        python3 - "$obj" <<'PYTHON_SCRIPT'
import sys
obj_file = sys.argv[1]
with open(obj_file, 'rb') as f:
    data = f.read()

# EBREAK encoding (little-endian): 73 00 10 00
# NOP encoding (addi x0,x0,0): 13 00 00 00
ebreak = b'\x73\x00\x10\x00'
nop = b'\x13\x00\x00\x00'

count = data.count(ebreak)
if count > 0:
    data = data.replace(ebreak, nop)
    with open(obj_file, 'wb') as f:
        f.write(data)
    print(f'  Replaced {count} occurrences')
PYTHON_SCRIPT
        PATCHED=$((PATCHED + 1))
    fi
done

echo "Patched $PATCHED object files"

# Rebuild archive
echo "Rebuilding archive..."
cd "$OLDPWD"
rm -f "$LIBRARY"
ar rcs "$LIBRARY" "$TMPDIR"/*.o

# Verify
TOTAL_AFTER=0
cd "$TMPDIR"
for obj in *.o; do
    if [ -f "$obj" ]; then
        COUNT=$(riscv-none-elf-objdump -d "$obj" 2>/dev/null | grep -c "ebreak" || true)
        TOTAL_AFTER=$((TOTAL_AFTER + COUNT))
    fi
done

echo "Done!"
echo "Before: $TOTAL_BEFORE EBREAK instructions"
echo "After:  $TOTAL_AFTER EBREAK instructions"
