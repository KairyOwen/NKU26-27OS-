/* Temporary A-stage panic endpoint: no dependency on unfinished Trap code. */
#include <intr.h>
#include <kmonitor.h>
#include <stdio.h>

void kmonitor(struct trapframe *tf) {
    intr_disable();
    cprintf("[A stage] fatal: kernel monitor reached; stage validation failed\n");
    while (1) {
    }
}
