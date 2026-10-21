#ifndef __KERN_MM_BUDDY_PMM_H__
#define __KERN_MM_BUDDY_PMM_H__

#include <pmm.h>

/* Lab 2, assigned to 2410683: Buddy System PMM interface.
 * buddy_pmm_manager registers the allocator; buddy_check() is the
 * self-designed black-box test invoked through the manager's check hook. */
extern const struct pmm_manager buddy_pmm_manager;
void buddy_check(void);

#endif
