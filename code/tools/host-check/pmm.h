#ifndef HOST_PMM_H
#define HOST_PMM_H
#include <assert.h>
#include <stdio.h>
#include <defs.h>
#include <list.h>
#define cprintf printf
#define PGSIZE 4096
struct Page {
    int ref;
    uint64_t flags;
    unsigned int property;
    list_entry_t page_link;
};
typedef struct { list_entry_t free_list; unsigned int nr_free; } free_area_t;
#define SetPageReserved(p) ((p)->flags |= 1ULL)
#define PageReserved(p) ((p)->flags & 1ULL)
#define ClearPageReserved(p) ((p)->flags &= ~1ULL)
#define SetPageProperty(p) ((p)->flags |= 2ULL)
#define PageProperty(p) ((p)->flags & 2ULL)
#define ClearPageProperty(p) ((p)->flags &= ~2ULL)
#define le2page(le, member) to_struct(le, struct Page, member)
struct pmm_manager {
    const char *name;
    void (*init)(void);
    void (*init_memmap)(struct Page *, size_t);
    struct Page *(*alloc_pages)(size_t);
    void (*free_pages)(struct Page *, size_t);
    size_t (*nr_free_pages)(void);
    void (*check)(void);
};
extern struct Page *pages;
extern size_t npage;
extern const size_t nbase;
extern const struct pmm_manager *pmm_manager;
static inline ppn_t page2ppn(struct Page *p) { return p - pages + nbase; }
static inline uintptr_t page2pa(struct Page *p) { return page2ppn(p) * PGSIZE; }
static inline int page_ref(struct Page *p) { return p->ref; }
static inline void set_page_ref(struct Page *p, int n) { p->ref = n; }
struct Page *alloc_pages(size_t n);
void free_pages(struct Page *p, size_t n);
size_t nr_free_pages(void);
#define alloc_page() alloc_pages(1)
#define free_page(p) free_pages(p, 1)
#endif
