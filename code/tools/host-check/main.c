#include <pmm.h>
#include <best_fit_pmm.h>
#include <buddy_pmm.h>

static struct Page real_pages[4096];
struct Page *pages = real_pages;
size_t npage;
const size_t nbase = 0x80000;
const struct pmm_manager *pmm_manager;
struct Page *alloc_pages(size_t n) { return pmm_manager->alloc_pages(n); }
void free_pages(struct Page *p, size_t n) { pmm_manager->free_pages(p, n); }
size_t nr_free_pages(void) { return pmm_manager->nr_free_pages(); }

static void setup(const struct pmm_manager *manager) {
    pages = real_pages;
    npage = nbase + 4096;
    pmm_manager = manager;
    manager->init();
    for (size_t i = 0; i < 4096; i++) {
        pages[i].flags = 0;
        pages[i].property = 0;
        pages[i].ref = 0;
        SetPageReserved(pages + i);
    }
    manager->init_memmap(pages + 17, 4079);
}

static void exercise_fragmentation(void) {
    struct Page *held[64] = {0};
    size_t requests[64] = {0};
    size_t initial = nr_free_pages();
    unsigned int seed = 1907;
    for (size_t step = 0; step < 10000; step++) {
        seed = seed * 1664525U + 1013904223U;
        size_t slot = (seed >> 16) % 64;
        if (held[slot] != NULL) {
            free_pages(held[slot], requests[slot]);
            held[slot] = NULL;
        } else {
            size_t request = ((seed >> 24) % 33) + 1;
            struct Page *p = alloc_pages(request);
            if (p == NULL) continue;
            size_t actual = request;
            if (pmm_manager == &buddy_pmm_manager) {
                actual = 1;
                while (actual < request) actual *= 2;
            }
            assert(p >= pages + 17 && p + actual <= pages + 4096);
            for (size_t i = 0; i < 64; i++) {
                if (held[i] == NULL) continue;
                size_t other = requests[i];
                if (pmm_manager == &buddy_pmm_manager) {
                    other = 1;
                    while (other < requests[i]) other *= 2;
                }
                assert(p + actual <= held[i] || held[i] + other <= p);
            }
            held[slot] = p;
            requests[slot] = request;
        }
    }
    for (size_t i = 0; i < 64; i++) {
        if (held[i] != NULL) free_pages(held[i], requests[i]);
    }
    assert(nr_free_pages() == initial);
    printf("%s: 10000 mixed operations, no overlap, accounting restored: PASS\n", pmm_manager->name);
}

int main(void) {
    setup(&best_fit_pmm_manager);
    pmm_manager->check();
    puts("Unmodified Best-Fit framework tests: PASS (host adapter)");
    exercise_fragmentation();
    setup(&buddy_pmm_manager);
    pmm_manager->check();
    exercise_fragmentation();
    puts("HOST ALGORITHM CHECKS PASSED; guest boot/page_init not tested here.");
    return 0;
}
