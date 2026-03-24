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

// Inline ecall helpers for SP1 syscalls used by evmone.
// Eliminates jal/ret overhead (~8 cycles) at each C++ call site.
#define SP1_ECALL_2ARG(name, num)                                              \
    [[gnu::always_inline]] inline void name(                                   \
        uint64_t *_p, const uint64_t *_q) noexcept {                           \
        register uint64_t t0 asm("t0") = (num);                               \
        register uint64_t *a0 asm("a0") = _p;                                 \
        register const uint64_t *a1 asm("a1") = _q;                           \
        asm volatile("ecall" : "+r"(t0) : "r"(a0), "r"(a1) : "memory");       \
    }

#define SP1_ECALL_1ARG(name, num)                                              \
    [[gnu::always_inline]] inline void name(                                   \
        uint64_t *_p) noexcept {                                               \
        register uint64_t t0 asm("t0") = (num);                               \
        register uint64_t *a0 asm("a0") = _p;                                 \
        register uint64_t a1 asm("a1") = 0;                                   \
        asm volatile("ecall" : "+r"(t0) : "r"(a0), "r"(a1) : "memory");       \
    }

SP1_ECALL_2ARG(syscall_sha256_compress, 0x00010106)
SP1_ECALL_1ARG(syscall_sha256_extend,   0x00300105)

SP1_ECALL_2ARG(syscall_secp256k1_add,    0x0001010A)
SP1_ECALL_1ARG(syscall_secp256k1_double, 0x0000010B)

SP1_ECALL_2ARG(syscall_bn254_add,    0x0001010E)
SP1_ECALL_1ARG(syscall_bn254_double, 0x0000010F)

SP1_ECALL_2ARG(syscall_bn254_fp_addmod,  0x00010126)
SP1_ECALL_2ARG(syscall_bn254_fp_submod,  0x00010127)
SP1_ECALL_2ARG(syscall_bn254_fp_mulmod,  0x00010128)
SP1_ECALL_2ARG(syscall_bn254_fp2_addmod, 0x00010129)
SP1_ECALL_2ARG(syscall_bn254_fp2_submod, 0x0001012A)
SP1_ECALL_2ARG(syscall_bn254_fp2_mulmod, 0x0001012B)

SP1_ECALL_2ARG(syscall_uint256_mulmod, 0x0001011D)

// Syscalls provided by the Rust SP1 runtime (linked via extern "C").
extern "C"
{
    void syscall_write(uint32_t fd, const uint8_t *write_buf, size_t nbytes);
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

namespace sp1 {
inline void mulmod(intx::uint256 &x, std::span<const intx::uint256, 2> ym) noexcept {
    syscall_uint256_mulmod(reinterpret_cast<size_t *>(&x),
                           reinterpret_cast<const size_t *>(ym.data()));
}
} // namespace sp1

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
