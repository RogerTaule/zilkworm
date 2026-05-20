/* arena_malloc.cpp — minimal bump allocator + C++ operator new/delete.
 *
 * Provides malloc/free/calloc/realloc backed by a single bump pointer
 * into the [_kernel_heap_bottom, _kernel_heap_top] region defined by
 * zisk.ld. free() is a no-op (zkVM execution is single-shot — no
 * fragmentation to worry about).
 *
 * realloc() always reallocates a fresh block (cannot safely copy: the
 * bump allocator doesn't track sizes). Fine for simple growing
 * containers like std::vector that re-write all elements after realloc.
 *
 * Then routes the C++ operator new / delete family through malloc /
 * free, so `new T(...)` and `delete p` work in C++ code.
 */
#include <cstddef>
#include <new>

extern "C" char _kernel_heap_bottom;
extern "C" char _kernel_heap_top;

static char *arena_next = nullptr;

extern "C" void *malloc(std::size_t size) {
    if (!arena_next) arena_next = &_kernel_heap_bottom;
    /* 8-byte align allocations */
    size = (size + 7) & ~static_cast<std::size_t>(7);
    char *p = arena_next;
    if (p + size > &_kernel_heap_top) return nullptr;  /* OOM */
    arena_next += size;
    return p;
}

extern "C" void free(void *p) { (void)p; /* no-op */ }

extern "C" void *calloc(std::size_t n, std::size_t size) {
    std::size_t total = n * size;
    char *p = static_cast<char *>(malloc(total));
    if (p) for (std::size_t i = 0; i < total; ++i) p[i] = 0;
    return p;
}

extern "C" void *realloc(void *old, std::size_t new_size) {
    /* Bump allocator doesn't track sizes; can't copy. Return fresh
     * block and let caller deal with it. This works for libc internals
     * and common growing-container patterns. */
    (void)old;
    return malloc(new_size);
}

/* C++ operator new / delete family.
 * All routed through malloc / free above. With -fno-exceptions, the
 * compiler turns out-of-memory into abort() rather than throwing
 * std::bad_alloc, so we don't need to handle that. */
void *operator new(std::size_t n)              { return malloc(n); }
void *operator new[](std::size_t n)            { return malloc(n); }
void  operator delete(void *p) noexcept        { free(p); }
void  operator delete[](void *p) noexcept      { free(p); }
void  operator delete(void *p, std::size_t) noexcept   { free(p); }
void  operator delete[](void *p, std::size_t) noexcept { free(p); }
