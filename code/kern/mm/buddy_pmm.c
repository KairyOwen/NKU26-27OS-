#include <buddy_pmm.h>
#include <stdio.h>

/* Lab 2, assigned to 2410683. Blocks align to physical page numbers. */
#define BUDDY_MAX_ORDER 15
#define BUDDY_ALLOCATED (1UL << 2)

static list_entry_t orders[BUDDY_MAX_ORDER + 1];
static size_t free_count;

static unsigned int request_order(size_t n) {
    unsigned int order = 0;
    while (order < BUDDY_MAX_ORDER && ((size_t)1 << order) < n) {
        order++;
    }
    return order;
}

static void buddy_init(void) {
    for (unsigned int i = 0; i <= BUDDY_MAX_ORDER; i++) {
        list_init(&orders[i]);
    }
    free_count = 0;
}

static void add_block(struct Page *p, unsigned int order) {
    p->property = (size_t)1 << order;
    SetPageProperty(p);
    list_add(&orders[order], &p->page_link);
}

static void merge_block(struct Page *p, unsigned int order) {
    while (order < BUDDY_MAX_ORDER) {
        size_t count = (size_t)1 << order;
        ppn_t peer_ppn = page2ppn(p) ^ count;
        if (peer_ppn < nbase || peer_ppn >= npage || count > npage - peer_ppn) {
            break;
        }
        struct Page *peer = pages + (peer_ppn - nbase);
        if (!PageProperty(peer) || peer->property != count) {
            break;
        }
        list_del(&peer->page_link);
        ClearPageProperty(peer);
        peer->property = 0;
        if (peer < p) {
            p = peer;
        }
        order++;
    }
    add_block(p, order);
}

static void buddy_init_memmap(struct Page *base, size_t n) {
    assert(n > 0 && base >= pages && base < pages + (npage - nbase));
    assert(n <= (size_t)(pages + (npage - nbase) - base));
    for (struct Page *p = base; p != base + n; p++) {
        assert(PageReserved(p));
        p->flags = 0;
        p->property = 0;
        set_page_ref(p, 0);
    }
    free_count += n;
    while (n != 0) {
        unsigned int order = 0;
        while (order < BUDDY_MAX_ORDER) {
            size_t next = (size_t)1 << (order + 1);
            if (next > n || page2ppn(base) % next != 0) {
                break;
            }
            order++;
        }
        size_t count = (size_t)1 << order;
        merge_block(base, order);
        base += count;
        n -= count;
    }
}

static struct Page *buddy_alloc_pages(size_t n) {
    assert(n > 0);
    if (n > ((size_t)1 << BUDDY_MAX_ORDER)) {
        return NULL;
    }
    unsigned int want = request_order(n), found = want;
    size_t count = (size_t)1 << want;
    if (count > free_count) {
        return NULL;
    }
    while (found <= BUDDY_MAX_ORDER && list_empty(&orders[found])) {
        found++;
    }
    if (found > BUDDY_MAX_ORDER) {
        return NULL;
    }
    struct Page *p = le2page(list_next(&orders[found]), page_link);
    list_del(&p->page_link);
    ClearPageProperty(p);
    p->property = 0;
    while (found > want) {
        found--;
        add_block(p + ((size_t)1 << found), found);
    }
    /* Save the original request; free_pages must receive exactly that n. */
    p->flags |= BUDDY_ALLOCATED;
    p->property = n;
    free_count -= count;
    return p;
}

static void buddy_free_pages(struct Page *base, size_t n) {
    assert(n > 0 && n <= ((size_t)1 << BUDDY_MAX_ORDER));
    assert(base >= pages && base < pages + (npage - nbase));
    assert((base->flags & BUDDY_ALLOCATED) && base->property == n);
    unsigned int order = request_order(n);
    size_t count = (size_t)1 << order;
    assert(page2ppn(base) % count == 0);
    assert(count <= (size_t)(pages + (npage - nbase) - base));
    for (struct Page *p = base; p != base + count; p++) {
        assert(!PageReserved(p) && !PageProperty(p) && page_ref(p) == 0);
        p->flags = 0;
        p->property = 0;
    }
    free_count += count;
    merge_block(base, order);
}

static size_t buddy_nr_free_pages(void) {
    return free_count;
}

const struct pmm_manager buddy_pmm_manager = {
    .name = "buddy_pmm_manager",
    .init = buddy_init,
    .init_memmap = buddy_init_memmap,
    .alloc_pages = buddy_alloc_pages,
    .free_pages = buddy_free_pages,
    .nr_free_pages = buddy_nr_free_pages,
    .check = buddy_check,
};
