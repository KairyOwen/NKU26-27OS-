/* A-stage harness, copied into a temporary tree only. Not a Trap test. */
#include <assert.h>
#include <console.h>
#include <dtb.h>
#include <intr.h>
#include <pmm.h>
#include <riscv.h>
#include <sbi.h>
#include <stdio.h>
#include <string.h>

int kern_init(void) __attribute__((noreturn));

int kern_init(void) {
    extern char edata[], end[];
    memset(edata, 0, end - edata);
    intr_disable();
    dtb_init();
    cons_init();
    cprintf("[A stage] physical memory integration only\n");
    pmm_init();

    size_t before = nr_free_pages();
    assert(before >= 3);
    assert((read_csr(sstatus) & SSTATUS_SIE) == 0);
    struct Page *block = alloc_pages(3);
    assert(block != NULL);
    assert(nr_free_pages() == before - 3);
    free_pages(block, 3);
    assert(nr_free_pages() == before);
    assert((read_csr(sstatus) & SSTATUS_SIE) == 0);
    cprintf("[A stage] allocation/accounting and disabled SIE preserved: PASS\n");
    cprintf("[A stage] PASS; Trap and timer tests remain for B/C\n");
    sbi_shutdown();
    while (1) {
    }
}
