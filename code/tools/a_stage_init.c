/* Temporary entry for A-only validation; never replaces the submitted entry. */
#include <defs.h>
#include <assert.h>
#include <string.h>
#include <console.h>
#include <dtb.h>
#include <intr.h>
#include <trap.h>
#include <pmm.h>
#include <vmm.h>
#include <stdio.h>
#include <sbi.h>
#include <error.h>

static const struct pmm_manager *real_manager;
static int allocation_budget;
static struct Page *limited_alloc(size_t n) {
    if (allocation_budget == 0) return NULL;
    allocation_budget--;
    return real_manager->alloc_pages(n);
}

int kern_init(void) __attribute__((noreturn));
int kern_init(void) {
    extern char edata[], end[];
    memset(edata, 0, end - edata);
    intr_disable();
    dtb_init();
    cons_init();
    idt_init();
    pmm_init();
    vmm_init();
    size_t initial = nr_free_pages();
    struct Page *root = alloc_page(), *data = alloc_page();
    assert(root && data);
    pde_t *pgdir = page2kva(root);
    memset(pgdir, 0, PGSIZE);
    set_page_ref(data, 0);
    assert(page_insert(pgdir, data, 0x4000, PTE_R | PTE_W) == 0);
    assert(page_ref(data) == 1);
    assert(page_insert(pgdir, data, 0x4000, PTE_R) == 0);
    assert(page_ref(data) == 1);
    pte_t *pte = get_pte(pgdir, 0x4000, 0);
    assert((*pte & PTE_W) == 0);
    page_remove(pgdir, 0x4000);
    page_remove(pgdir, 0x4000);
    page_remove(pgdir, (uintptr_t)1 << 30);
    pde_t *middle = KADDR(PDE_ADDR(pgdir[0]));
    free_page(pde2page(middle[0]));
    free_page(pde2page(pgdir[0]));
    free_page(root);
    assert(nr_free_pages() == initial);
    cprintf("[A] same-page remap, permissions, idempotent remove, accounting: PASS\n");

    root = alloc_page();
    data = alloc_page();
    assert(root && data);
    pgdir = page2kva(root);
    memset(pgdir, 0, PGSIZE);
    set_page_ref(data, 0);
    real_manager = pmm_manager;
    struct pmm_manager limited = *real_manager;
    limited.alloc_pages = limited_alloc;
    size_t before_failure = nr_free_pages();
    for (int budget = 0; budget <= 1; budget++) {
        allocation_budget = budget;
        pmm_manager = &limited;
        assert(page_insert(pgdir, data, 0, PTE_R) == -E_NO_MEM);
        pmm_manager = real_manager;
        assert(page_ref(data) == 0 && pgdir[0] == 0);
        assert(nr_free_pages() == before_failure);
    }
    free_page(data);
    free_page(root);
    assert(nr_free_pages() == initial);
    cprintf("[A] first/second page-table allocation failure rollback: PASS\n");

    asm volatile(".option push\n.option norvc\nebreak\n.option pop");
    asm volatile(".2byte 0x9002");
    cprintf("[A] 32-bit and compressed breakpoint return: PASS\n");
    cprintf("[A] physical memory, page tables and VMA: PASS\n");
    cprintf("[A] process creation and scheduling remain for B/C\n");
    sbi_shutdown();
    while (1) {}
}
