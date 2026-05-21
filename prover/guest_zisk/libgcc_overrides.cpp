// libgcc_overrides.cpp — replace libgcc software helpers with native rv64IM ops.
//
// Why this exists: our -march=rv64ima_zicsr target doesn't match any exact
// libgcc multilib in the xPack riscv-none-elf-gcc 15.2 distribution, so the
// link picks lib/gcc/.../rv64ia_zaamo_zalrsc/lp64/libgcc.a — a variant
// without the M (multiply) extension. Every call site that lowers to a
// __muldi3 / __multi3 / __udivdi3 / __umoddi3 / __divdi3 / __moddi3 /
// __udivti3 helper therefore executes a 30–50 instruction software
// shift-and-add loop instead of the single rv64IM `mul` / `div` / `rem`
// instruction the chip supports.
//
// Audit on the post-arith256 build:
//     __muldi3     :  162 call sites
//     __multi3     :  110 call sites
//     __udivdi3    :  146 call sites
//     __umoddi3    :   71 call sites
//     __divdi3     :   96 call sites
//     __moddi3     :  102 call sites
//     __udivti3    :   92 call sites
//     __clzdi2     :   87 call sites  (no native CLZ outside Zbb; we still
//                                       provide an inlined binary search)
//     __ctzdi2     :   19 call sites
//     __popcountdi2:    4 call sites
//                  ──────
//                    889 call sites total.
//
// This translation unit is built with the same rv64ima_zicsr flags as the
// rest of the guest, so the simple operator-based implementations below
// compile to a single native instruction (`mul`, `divu`, `remu`, `mulh`,
// …). The linker picks our definitions over libgcc's because object files
// are searched before static archives.

#include <cstdint>

extern "C"
{
// ─── 64-bit multiply (low half) ──────────────────────────────────────
// GCC on rv64IM lowers `int64_t * int64_t` to a single `mul` instruction.
int64_t __muldi3(int64_t a, int64_t b) noexcept { return a * b; }
uint64_t __umuldi3(uint64_t a, uint64_t b) noexcept { return a * b; }

// ─── 64-bit divide / modulo ──────────────────────────────────────────
// Lower directly to `div`/`divu`/`rem`/`remu`.
uint64_t __udivdi3(uint64_t a, uint64_t b) noexcept { return a / b; }
uint64_t __umoddi3(uint64_t a, uint64_t b) noexcept { return a % b; }
int64_t __divdi3(int64_t a, int64_t b) noexcept { return a / b; }
int64_t __moddi3(int64_t a, int64_t b) noexcept { return a % b; }

// ─── 128-bit multiply (low half) ─────────────────────────────────────
// GCC inlines this as a mul/mulhu sequence for the cross terms.
__int128 __multi3(__int128 a, __int128 b) noexcept { return a * b; }

// ─── 128-bit unsigned divide ─────────────────────────────────────────
// We intentionally do NOT override __udivti3 here. GCC compiles a /= b
// for unsigned __int128 by emitting a call to __udivti3, which means a
// naive `return a / b;` override would recurse infinitely. Leaving it
// to libgcc's software implementation is correct; we can revisit with a
// proper shift-subtract 128-bit divider if the call frequency turns out
// to be high enough to matter.

// ─── Bit-counting helpers (no native rv64IM equivalent) ──────────────
// We hand-roll the binary-search forms — same shape libgcc would emit,
// but visible to the optimiser at every caller (avoids the JAL + epilogue).
int __clzdi2(uint64_t v) noexcept
{
    if (v == 0)
        return 64;
    int n = 0;
    if ((v >> 32) == 0) { n += 32; v <<= 32; }
    if ((v >> 48) == 0) { n += 16; v <<= 16; }
    if ((v >> 56) == 0) { n +=  8; v <<=  8; }
    if ((v >> 60) == 0) { n +=  4; v <<=  4; }
    if ((v >> 62) == 0) { n +=  2; v <<=  2; }
    if ((v >> 63) == 0) { n +=  1; }
    return n;
}

int __ctzdi2(uint64_t v) noexcept
{
    if (v == 0)
        return 64;
    int n = 0;
    if ((v & 0xFFFFFFFFULL) == 0) { n += 32; v >>= 32; }
    if ((v & 0x0000FFFFULL) == 0) { n += 16; v >>= 16; }
    if ((v & 0x000000FFULL) == 0) { n +=  8; v >>=  8; }
    if ((v & 0x0000000FULL) == 0) { n +=  4; v >>=  4; }
    if ((v & 0x00000003ULL) == 0) { n +=  2; v >>=  2; }
    if ((v & 0x00000001ULL) == 0) { n +=  1; }
    return n;
}

// SWAR popcount — eight summed half-byte counts in one 64-bit multiply.
int __popcountdi2(uint64_t v) noexcept
{
    v = v - ((v >> 1) & 0x5555555555555555ULL);
    v = (v & 0x3333333333333333ULL) + ((v >> 2) & 0x3333333333333333ULL);
    v = (v + (v >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
    return static_cast<int>((v * 0x0101010101010101ULL) >> 56);
}

}  // extern "C"
