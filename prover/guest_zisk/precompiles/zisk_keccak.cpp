/* zisk_keccak.cpp — Zisk syscall override for the Keccak-f[1600] permutation.
 *
 * Keccak is the primitive behind the EVM's KECCAK256 opcode (formerly
 * SHA3) and is also used internally for every account hash, storage
 * key, and Merkle-Patricia trie node hash. Replacing the inner
 * permutation step with Zisk's native precompile is the single biggest
 * perf lever for any non-trivial mainnet block.
 *
 * Zisk's syscall ABI (from /tmp/zisk-v0.17.0/ziskos/entrypoint/src/syscalls/keccakf.rs):
 *
 *   pub unsafe extern "C" fn syscall_keccak_f(state: *mut [u64; 25]);
 *   `csrs 0x800, <reg holding state ptr>`
 *
 * Compared to sha256_f (which needs a small params struct holding two
 * pointers), keccak_f is even simpler: a single 25-u64 (200-byte) state
 * buffer, permuted in place. The portable code in evmone's keccak.c
 * already handles absorb / pad / squeeze; we just provide the inner
 * f1600 step.
 *
 * Linked into z6m_guest.elf via prover/guest_zisk/CMakeLists.txt.
 * evmone picks it up via the `#elif defined(ZISK)` branch in keccak.c's
 * `DEFAULT_keccakf1600` dispatch macro.
 */
#include <cstdint>

namespace {

constexpr unsigned ZISK_SYSCALL_KECCAKF = 0x800;

}  // namespace

/// In-place Keccak-f[1600] permutation via Zisk syscall.
///
/// @param state  Pointer to a 25-element u64 array (200 bytes), naturally
///               8-byte aligned. The Zisk emulator reads + writes this
///               region directly during the precompile step.
extern "C" void syscall_keccak_permute(std::uint64_t state[25]) noexcept
{
    asm volatile("csrs %1, %0"
                 :
                 : "r"(state), "i"(ZISK_SYSCALL_KECCAKF)
                 : "memory");
}
