#include <list.h>
#include <sync.h>
#include <proc.h>
#include <sched.h>
#include <assert.h>

void
wakeup_proc(struct proc_struct *proc) {
    assert(proc->state != PROC_ZOMBIE && proc->state != PROC_RUNNABLE);
    proc->state = PROC_RUNNABLE;
}

void switch_to(struct context *from, struct context *to);

void
schedule(void) {
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        current->need_resched = 0;
        struct proc_struct *next = NULL;
        list_entry_t *le = &proc_list;
        while ((le = list_next(le)) != &proc_list) {
            struct proc_struct *p = le2proc(le, list_link);
            if (p->state == PROC_RUNNABLE) {
                if (next == NULL || p->runs < next->runs) {
                    next = p;
                }
            }
        }
        if (next == NULL) {
            next = idleproc;
        }
        next->runs++;
        if (next != current) {
            proc_run(next);
        }
    }
    local_intr_restore(intr_flag);
}

void
proc_run(struct proc_struct *proc) {
    if (proc != current) {
        bool intr_flag;
        struct proc_struct *prev = current;
        local_intr_save(intr_flag);
        {
            current = proc;
            switch_to(&(prev->context), &(proc->context));
        }
        local_intr_restore(intr_flag);
    }
}

void
cpu_idle(void) {
    while (1) {
        if (current->need_resched) {
            schedule();
        }
    }
}


