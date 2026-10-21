#include <buddy_pmm.h>
#include <stdio.h>

/* Lab 2, assigned to 2410683. Black-box tests use only manager callbacks. */
static struct Page arena[80];

static size_t rounded_pages(size_t n) {
    size_t count = 1;
    while (count < n) {
        count *= 2;
    }
    return count;
}

static void reset_arena(size_t first, size_t count) {
    buddy_pmm_manager.init();
    for (size_t i = 0; i < 80; i++) {
        arena[i].flags = 0;
        arena[i].property = 0;
        set_page_ref(arena + i, 0);
        SetPageReserved(arena + i);
    }
    buddy_pmm_manager.init_memmap(arena + first, count);
    assert(buddy_pmm_manager.nr_free_pages() == count);
}

static void check_isolated(void) {
    struct Page *saved_pages = pages;
    size_t saved_npage = npage;
    pages = arena;
    npage = nbase + 80;

    reset_arena(0, 32);
    struct Page *p = buddy_pmm_manager.alloc_pages(3);
    struct Page *q = buddy_pmm_manager.alloc_pages(8);
    assert(p != NULL && q != NULL);
    assert(page2ppn(p) % 4 == 0 && page2ppn(q) % 8 == 0);
    assert(p + 4 <= q || q + 8 <= p);
    assert(buddy_pmm_manager.nr_free_pages() == 20);
    buddy_pmm_manager.free_pages(p, 3);
    buddy_pmm_manager.free_pages(q, 8);
    p = buddy_pmm_manager.alloc_pages(32);
    assert(p == arena && buddy_pmm_manager.nr_free_pages() == 0);
    assert(buddy_pmm_manager.alloc_pages(1) == NULL);
    buddy_pmm_manager.free_pages(p, 32);
    cprintf("[Buddy] rounding, split, recursive merge: PASS\n");

    reset_arena(1, 2);
    assert(buddy_pmm_manager.nr_free_pages() == 2);
    assert(buddy_pmm_manager.alloc_pages(2) == NULL);
    p = buddy_pmm_manager.alloc_pages(1);
    q = buddy_pmm_manager.alloc_pages(1);
    assert(p != NULL && q != NULL && p != q);
    buddy_pmm_manager.free_pages(p, 1);
    buddy_pmm_manager.free_pages(q, 1);
    assert(buddy_pmm_manager.alloc_pages(2) == NULL);
    cprintf("[Buddy] adjacent non-buddies stay separate: PASS\n");

    reset_arena(3, 61);
    struct Page *held[61];
    for (size_t i = 0; i < 61; i++) {
        held[i] = buddy_pmm_manager.alloc_pages(1);
        assert(held[i] >= arena + 3 && held[i] < arena + 64);
        assert(!PageReserved(held[i]) && page_ref(held[i]) == 0);
        for (size_t j = 0; j < i; j++) {
            assert(held[i] != held[j]);
        }
    }
    assert(buddy_pmm_manager.alloc_pages(1) == NULL);
    for (size_t i = 0; i < 61; i += 2) {
        buddy_pmm_manager.free_pages(held[i], 1);
    }
    for (size_t i = 1; i < 61; i += 2) {
        buddy_pmm_manager.free_pages(held[i], 1);
    }
    assert(buddy_pmm_manager.nr_free_pages() == 61);
    p = buddy_pmm_manager.alloc_pages(32);
    assert(p == arena + 32);
    buddy_pmm_manager.free_pages(p, 32);
    assert(buddy_pmm_manager.alloc_pages(62) == NULL);
    assert(buddy_pmm_manager.alloc_pages(32769) == NULL);
    cprintf("[Buddy] irregular range, exhaustion, no overlap: PASS\n");

    /* Restore the real address space; rebuild real lists in buddy_check. */
    pages = saved_pages;
    npage = saved_npage;
}

void buddy_check(void) {
    /* Initial free descriptors form one contiguous region from page_init. */
    struct Page *first = NULL;
    size_t initial = buddy_pmm_manager.nr_free_pages();
    for (size_t i = 0; i < npage - nbase; i++) {
        if (!PageReserved(pages + i)) {
            first = pages + i;
            break;
        }
    }
    assert(first != NULL && initial > 0);
    check_isolated();
    buddy_pmm_manager.init();
    for (struct Page *p = first; p != first + initial; p++) {
        p->flags = 0;
        p->property = 0;
        SetPageReserved(p);
    }
    buddy_pmm_manager.init_memmap(first, initial);

    const size_t requests[] = {1, 3, 7, 16, 31};
    struct Page *held[5];
    size_t consumed = 0;
    for (size_t i = 0; i < 5; i++) {
        held[i] = alloc_pages(requests[i]);
        assert(held[i] != NULL);
        size_t actual = rounded_pages(requests[i]);
        assert(held[i] >= first && held[i] + actual <= first + initial);
        assert(page2ppn(held[i]) % actual == 0);
        for (size_t j = 0; j < i; j++) {
            assert(held[i] + actual <= held[j] ||
                   held[j] + rounded_pages(requests[j]) <= held[i]);
        }
        consumed += actual;
        assert(nr_free_pages() == initial - consumed);
    }
    for (size_t i = 5; i > 0; i--) {
        free_pages(held[i - 1], requests[i - 1]);
    }
    assert(nr_free_pages() == initial);
    cprintf("[Buddy] real memory and accounting recovery: PASS\n");
    cprintf("[Buddy] ALL TESTS PASSED\n");
}
