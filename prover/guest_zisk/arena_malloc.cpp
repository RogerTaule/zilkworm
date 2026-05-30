/* C ABI glue: C++ malloc / new family forwards every allocation to
 * ziskos's bump allocator (sys_alloc_aligned). No separate C++ allocator.
 * Init order: _start.s runs init_sys_alloc before .init_array. */
#include <cstddef>
#include <cstring>
#include <new>

extern "C" void *sys_alloc_aligned(std::size_t bytes, std::size_t align);
extern "C" std::size_t sys_get_heap_pos();
extern "C" void sys_set_heap_pos(std::size_t pos);

// 16 = __STDCPP_DEFAULT_NEW_ALIGNMENT__ on rv64 lp64.
static constexpr std::size_t kDefaultAlign = 16;

extern "C" __attribute__((hot)) void *malloc(std::size_t size) {
    return sys_alloc_aligned(size, kDefaultAlign);
}

extern "C" void free(void *) { /* bump allocator — no-op */ }

extern "C" __attribute__((hot)) void *calloc(std::size_t n, std::size_t size) {
    const std::size_t total = n * size;
    void *p = sys_alloc_aligned(total, kDefaultAlign);
    if (p) std::memset(p, 0, total);
    return p;
}

extern "C" void *realloc(void *old, std::size_t new_size) {
    if (!old) return malloc(new_size);
    if (new_size == 0) { free(old); return nullptr; }
    void *fresh = sys_alloc_aligned(new_size, kDefaultAlign);
    // Preserves the original allocation's bytes — critical for growing
    // std::vector / newlib internal tables. We don't know the old size,
    // so copy new_size (trailing garbage the caller never touches).
    if (fresh) std::memcpy(fresh, old, new_size);
    return fresh;
}

extern "C" void *aligned_alloc(std::size_t alignment, std::size_t size) {
    return sys_alloc_aligned(size, alignment);
}

extern "C" int posix_memalign(void **out, std::size_t alignment, std::size_t size) {
    *out = sys_alloc_aligned(size, alignment);
    return *out ? 0 : 12; /* ENOMEM */
}

// EEST runner recycles arena memory between sub-tests via these.
extern "C" void *arena_checkpoint() noexcept {
    return reinterpret_cast<void *>(sys_get_heap_pos());
}
extern "C" void arena_rewind(void *checkpoint) noexcept {
    sys_set_heap_pos(reinterpret_cast<std::size_t>(checkpoint));
}

void *operator new(std::size_t n)              { return sys_alloc_aligned(n, kDefaultAlign); }
void *operator new[](std::size_t n)            { return sys_alloc_aligned(n, kDefaultAlign); }
void  operator delete(void *p) noexcept        { free(p); }
void  operator delete[](void *p) noexcept      { free(p); }
void  operator delete(void *p, std::size_t) noexcept   { free(p); }
void  operator delete[](void *p, std::size_t) noexcept { free(p); }

// C++17 aligned new — required for types with alignment > 16
// (e.g. evmone's `alignas(32) uint256 items[1024]`).
void *operator new(std::size_t n, std::align_val_t a) {
    return sys_alloc_aligned(n, static_cast<std::size_t>(a));
}
void *operator new[](std::size_t n, std::align_val_t a) {
    return sys_alloc_aligned(n, static_cast<std::size_t>(a));
}
void  operator delete(void *p, std::align_val_t) noexcept       { free(p); }
void  operator delete[](void *p, std::align_val_t) noexcept     { free(p); }
void  operator delete(void *p, std::size_t, std::align_val_t) noexcept   { free(p); }
void  operator delete[](void *p, std::size_t, std::align_val_t) noexcept { free(p); }
