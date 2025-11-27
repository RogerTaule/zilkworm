#pragma once
#include <cstddef> // size_t
#include <cstdint> // uint8_t, uint32_t, uint64_t
#include <cstring> // strlen

#include <intx/intx.hpp>

// Notes:
// - Rust `usize` <-> C++ `size_t`
// - Rust `u8/u32/u64` <-> C++ uint8_t/uint32_t/uint64_t
// - Rust pointer to fixed-size array like `*mut [u64; 8]`
//     becomes `uint64_t[8]` or `uint64_t (*)[8]` (pointer to array-of-8)
// - Rust `bool` in FFI is 1 byte (0 or 1). C++ `bool` is typically ABI-compatible,
//   but if you want to be extra cautious, you can swap `bool` for `uint8_t`.

// Rust: #[repr(C)]
struct ReadVecResult
{
    uint8_t *ptr;
    size_t len;
    size_t capacity;
};

using uintType = uint64_t;

extern "C"
{

    // pub fn syscall_halt(exit_code: u8) -> !
    [[noreturn]] void syscall_halt(uint8_t exit_code);

    // pub fn syscall_write(fd: u32, write_buf: *const u8, nbytes: usize)
    void syscall_write(uint32_t fd, const uint8_t *write_buf, size_t nbytes);

    // pub fn syscall_read(fd: u32, read_buf: *mut u8, nbytes: usize)
    void syscall_read(uint32_t fd, uint8_t *read_buf, size_t nbytes);

    // pub fn syscall_sha256_extend(w: *mut [u64; 64])
    void syscall_sha256_extend(uint64_t w[64]);

    // pub fn syscall_sha256_compress(w: *mut [u64; 64], state: *mut [u64; 8])
    void syscall_sha256_compress(uint64_t w[64], uint64_t state[8]);

    // pub fn syscall_ed_add(p: *mut [u64; 8], q: *const [u64; 8])
    void syscall_ed_add(uint64_t p[8], const uint64_t q[8]);

    // pub fn syscall_ed_decompress(point: &mut [u64; 8])
    void syscall_ed_decompress(uint64_t point[8]);

    // pub fn syscall_secp256k1_add(p: *mut [u64; 8], q: *const [u64; 8])
    void syscall_secp256k1_add(uint64_t p[8], const uint64_t q[8]);

    // pub fn syscall_secp256k1_double(p: *mut [u64; 8])
    void syscall_secp256k1_double(uint64_t p[8]);

    // pub fn syscall_secp256k1_decompress(point: &mut [u64; 8], is_odd: bool)
    void syscall_secp256k1_decompress(uint64_t point[8], bool is_odd);

    // pub fn syscall_secp256r1_add(p: *mut [u64; 8], q: *const [u64; 8])
    void syscall_secp256r1_add(uint64_t p[8], const uint64_t q[8]);

    // pub fn syscall_secp256r1_double(p: *mut [u64; 8])
    void syscall_secp256r1_double(uint64_t p[8]);

    // pub fn syscall_secp256r1_decompress(point: &mut [u64; 8], is_odd: bool)
    void syscall_secp256r1_decompress(uint64_t point[8], bool is_odd);

    // pub fn syscall_bn254_add(p: *mut [u64; 8], q: *const [u64; 8])
    void syscall_bn254_add(uint64_t p[8], const uint64_t q[8]);

    // pub fn syscall_bn254_double(p: *mut [u64; 8])
    void syscall_bn254_double(uint64_t p[8]);

    // pub fn syscall_bls12381_add(p: *mut [u64; 12], q: *const [u64; 12])
    void syscall_bls12381_add(uint64_t p[12], const uint64_t q[12]);

    // pub fn syscall_bls12381_double(p: *mut [u64; 12])
    void syscall_bls12381_double(uint64_t p[12]);

    // pub fn syscall_keccak_permute(state: *mut [u64; 25])
    void syscall_keccak_permute(uint64_t state[25]);

    // pub fn syscall_uint256_mulmod(x: *mut [u64; 4], y: *const [u64; 4])
    void syscall_uint256_mulmod(uint64_t x[4], const uint64_t y[4]);

    // pub fn syscall_u256x2048_mul(
    //     x: *const [u64; 4], y: *const [u64; 32], lo: *mut [u64; 32], hi: *mut [u64; 4])
    void syscall_u256x2048_mul(const uint64_t x[4],
                               const uint64_t y[32],
                               uint64_t lo[32],
                               uint64_t hi[4]);

    // pub fn syscall_uint256_add_with_carry(
    //     a: *const [u64; 4], b: *const [u64; 4], c: *const [u64; 4],
    //     d: *mut [u64; 4], e: *mut [u64; 4])
    void syscall_uint256_add_with_carry(const uint64_t a[4],
                                        const uint64_t b[4],
                                        const uint64_t c[4],
                                        uint64_t d[4],
                                        uint64_t e[4]);

    // pub fn syscall_uint256_mul_with_carry(
    //     a: *const [u64; 4], b: *const [u64; 4], c: *const [u64; 4],
    //     d: *mut [u64; 4], e: *mut [u64; 4])
    void syscall_uint256_mul_with_carry(const uint64_t a[4],
                                        const uint64_t b[4],
                                        const uint64_t c[4],
                                        uint64_t d[4],
                                        uint64_t e[4]);

    // pub fn syscall_enter_unconstrained() -> bool
    bool syscall_enter_unconstrained();

    // pub fn syscall_exit_unconstrained()
    void syscall_exit_unconstrained();

    // pub fn syscall_verify_sp1_proof(vk_digest: &[u64; 4], pv_digest: &[u64; 4])
    void syscall_verify_sp1_proof(const uint64_t vk_digest[4],
                                  const uint64_t pv_digest[4]);

    // pub fn syscall_hint_len() -> usize
    size_t syscall_hint_len();

    // pub fn syscall_hint_read(ptr: *mut u8, len: usize)
    void syscall_hint_read(uint8_t *ptr, size_t len);

    // pub fn sys_alloc_aligned(bytes: usize, align: usize) -> *mut u8
    uint8_t *sys_alloc_aligned(size_t bytes, size_t align);

    // pub fn syscall_bls12381_decompress(point: &mut [u64; 12], is_odd: bool)
    void syscall_bls12381_decompress(uint64_t point[12], bool is_odd);

    // pub fn sys_bigint(
    //   result: *mut [u64; 4], op: u64, x: *const [u64; 4], y: *const [u64; 4], modulus: *const [u64; 4])
    void sys_bigint(uint64_t result[4],
                    uint64_t op,
                    const uint64_t x[4],
                    const uint64_t y[4],
                    const uint64_t modulus[4]);

    // Field/Fp and Fp2 ops for BLS12-381 (operands are limb pointers; sizes defined by the ABI)
    // pub fn syscall_bls12381_fp_addmod(p: *mut u64, q: *const u64)
    void syscall_bls12381_fp_addmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bls12381_fp_submod(p: *mut u64, q: *const u64)
    void syscall_bls12381_fp_submod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bls12381_fp_mulmod(p: *mut u64, q: *const u64)
    void syscall_bls12381_fp_mulmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bls12381_fp2_addmod(p: *mut u64, q: *const u64)
    void syscall_bls12381_fp2_addmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bls12381_fp2_submod(p: *mut u64, q: *const u64)
    void syscall_bls12381_fp2_submod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bls12381_fp2_mulmod(p: *mut u64, q: *const u64)
    void syscall_bls12381_fp2_mulmod(uint64_t *p, const uint64_t *q);

    // Field/Fp and Fp2 ops for BN254
    // pub fn syscall_bn254_fp_addmod(p: *mut u64, q: *const u64)
    void syscall_bn254_fp_addmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bn254_fp_submod(p: *mut u64, q: *const u64)
    void syscall_bn254_fp_submod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bn254_fp_mulmod(p: *mut u64, q: *const u64)
    void syscall_bn254_fp_mulmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bn254_fp2_addmod(p: *mut u64, q: *const u64)
    void syscall_bn254_fp2_addmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bn254_fp2_submod(p: *mut u64, q: *const u64)
    void syscall_bn254_fp2_submod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_bn254_fp2_mulmod(p: *mut u64, q: *const u64)
    void syscall_bn254_fp2_mulmod(uint64_t *p, const uint64_t *q);

    // pub fn syscall_mprotect(addr: *const u8, prot: u8)
    void syscall_mprotect(const uint8_t *addr, uint8_t prot);

    // pub fn read_vec_raw() -> ReadVecResult
    ReadVecResult read_vec_raw();
} // extern "C"

static inline void sys_print(const char *s)
{
    syscall_write(1, reinterpret_cast<const uint8_t *>(s), std::strlen(s));
}
static inline void sys_println(const char *s)
{
    syscall_write(1, reinterpret_cast<const uint8_t *>(s), std::strlen(s));
    syscall_write(1, reinterpret_cast<const uint8_t *>("\n"), 1);
}

// Note: Affine points are now uint64_t[8] (not uint32_t[16])
using sp1_AffinePoint = uint64_t[8];

inline bool is_zero(const sp1_AffinePoint p) noexcept
{
    uint64_t fold = 0;
    for (size_t i = 0; i < 8; ++i)
        fold |= p[i];
    return fold == 0;
}

inline bool eq(const sp1_AffinePoint p, const sp1_AffinePoint q) noexcept
{
    uint64_t fold = 0;
    for (size_t i = 0; i < 8; ++i)
        fold |= p[i] ^ q[i];
    return fold == 0;
}

inline void sp1_point_from_bytes(sp1_AffinePoint r, const uint8_t bytes[64]) noexcept
{
    const auto x = &bytes[0];
    const auto y = &bytes[32];
    for (size_t i = 0; i < 4; ++i)
        r[i] = intx::be::unsafe::load<uint64_t>(&x[32 - (i + 1) * 8]);
    for (size_t i = 0; i < 4; ++i)
        r[i + 4] = intx::be::unsafe::load<uint64_t>(&y[32 - (i + 1) * 8]);
}

inline void sp1_point_to_bytes(uint8_t bytes[64], const sp1_AffinePoint r) noexcept
{
    const auto x = &bytes[0];
    const auto y = &bytes[32];
    for (size_t i = 0; i < 4; ++i)
        intx::be::unsafe::store(&x[32 - (i + 1) * 8], r[i]);
    for (size_t i = 0; i < 4; ++i)
        intx::be::unsafe::store<uint64_t>(&y[32 - (i + 1) * 8], r[i + 4]);
}
