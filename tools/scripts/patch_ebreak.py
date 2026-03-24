#!/usr/bin/env python3
"""
Patch EBREAK instructions (RISC-V 64) inside executable code segments of an ELF64 little-endian file.

Usage:
    python3 scripts/patch_ebreak.py /path/to/z6m_guest [--dry-run] [--backup]

What it does:
- Reads the ELF program headers and locates PT_LOAD segments with execute permission.
- Scans each executable segment for the 4-byte little-endian pattern of EBREAK (\x73\x00\x10\x00).
- Replaces each found occurrence with a safe NOP encoding (addi x0,x0,0 -> \x13\x00\x00\x00).
- Writes a backup (if requested) and prints a short report listing patched virtual addresses and file offsets.

WARNING: This mutates the ELF binary. Make a backup and test thoroughly. This is a last-resort workaround; fixing the root cause in source is preferable.

"""
import sys
import struct
import shutil
from pathlib import Path

def read_elf_header(f):
    f.seek(0)
    e_ident = f.read(16)
    if len(e_ident) < 16 or e_ident[0:4] != b'\x7fELF':
        raise SystemExit('Not an ELF file')
    ei_class = e_ident[4]
    ei_data = e_ident[5]
    if ei_class != 2:
        raise SystemExit('Only ELF64 is supported by this script')
    if ei_data != 1:
        raise SystemExit('Only little-endian ELF is supported')
    # ELF64 header offsets
    f.seek(32)
    e_phoff = struct.unpack('<Q', f.read(8))[0]
    f.seek(54)
    e_phentsize = struct.unpack('<H', f.read(2))[0]
    e_phnum = struct.unpack('<H', f.read(2))[0]
    return e_phoff, e_phentsize, e_phnum

def parse_program_headers(f, e_phoff, e_phentsize, e_phnum):
    headers = []
    f.seek(e_phoff)
    for i in range(e_phnum):
        data = f.read(e_phentsize)
        if len(data) < 56:
            raise SystemExit('Program header too short')
        # Elf64_Phdr: p_type (4), p_flags (4), p_offset (8), p_vaddr (8), p_paddr (8), p_filesz (8), p_memsz (8), p_align (8)
        p_type, p_flags = struct.unpack_from('<II', data, 0)
        p_offset = struct.unpack_from('<Q', data, 8)[0]
        p_vaddr = struct.unpack_from('<Q', data, 16)[0]
        p_paddr = struct.unpack_from('<Q', data, 24)[0]
        p_filesz = struct.unpack_from('<Q', data, 32)[0]
        p_memsz = struct.unpack_from('<Q', data, 40)[0]
        p_align = struct.unpack_from('<Q', data, 48)[0]
        headers.append({
            'p_type': p_type,
            'p_flags': p_flags,
            'p_offset': p_offset,
            'p_vaddr': p_vaddr,
            'p_paddr': p_paddr,
            'p_filesz': p_filesz,
            'p_memsz': p_memsz,
            'p_align': p_align,
        })
    return headers

PT_LOAD = 1
PF_X = 1

TARGET = b'\x73\x00\x10\x00'   # ebreak (little-endian)
REPLACEMENT = b'\x13\x00\x00\x00'  # addi x0,x0,0 (nop)


def patch_file(path: Path, dry_run=False, backup=True):
    if not path.exists():
        raise SystemExit(f'File not found: {path}')
    if backup:
        bak = path.with_suffix(path.suffix + '.bak')
        print(f'creating backup: {bak}')
        shutil.copy2(path, bak)
    with open(path, 'r+b') as f:
        e_phoff, e_phentsize, e_phnum = read_elf_header(f)
        headers = parse_program_headers(f, e_phoff, e_phentsize, e_phnum)
        total_patched = 0
        patched_locations = []
        for h in headers:
            if h['p_type'] != PT_LOAD:
                continue
            if (h['p_flags'] & PF_X) == 0:
                continue
            off = h['p_offset']
            size = h['p_filesz']
            vaddr = h['p_vaddr']
            if size == 0:
                continue
            print(f'Scanning exec segment at file_offset=0x{off:x} size=0x{size:x} vaddr=0x{vaddr:x}')
            f.seek(off)
            data = f.read(size)
            # Scan on 4-byte instruction alignment
            for i in range(0, len(data) - 3, 4):
                if data[i:i+4] == TARGET:
                    file_pos = off + i
                    virt_addr = vaddr + i
                    print(f'  Found EBREAK at file_offset=0x{file_pos:x} vaddr=0x{virt_addr:x}')
                    patched_locations.append((file_pos, virt_addr))
                    total_patched += 1
                    if not dry_run:
                        f.seek(file_pos)
                        f.write(REPLACEMENT)
                        # ensure we also update in local data buffer to avoid double-patch issues
                        data = data[:i] + REPLACEMENT + data[i+4:]
        print(f'patched {total_patched} instruction(s)')
        return patched_locations

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    path = Path(sys.argv[1])
    dry = '--dry-run' in sys.argv
    backup = '--no-backup' not in sys.argv
    locs = patch_file(path, dry_run=dry, backup=backup)
    if locs:
        print('\nPatched locations:')
        for fp, va in locs:
            print(f'  file_offset=0x{fp:x} vaddr=0x{va:x}')
    else:
        print('No occurrences found.')
