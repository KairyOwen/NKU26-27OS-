# Host-side allocator checks

This adapter compiles the delivered allocator sources without changing them.
The kernel list implementation is copied unchanged. The small pmm.h/defs.h
adapters replace privileged/platform dependencies with host types and assertions.
This does not test page_init, DTB, RISC-V instructions, or guest boot.

On a Linux host, from code/:

```bash
cc -std=c11 -Itools/host-check -Ikern/mm \
  tools/host-check/main.c kern/mm/best_fit_pmm.c \
  kern/mm/buddy_pmm.c kern/mm/buddy_check.c -o /tmp/lab2-host-check
/tmp/lab2-host-check
```

On Windows, run the same sources in an x64 Visual Studio Developer Command Prompt:

```text
cl /nologo /std:c11 /I tools\host-check /I kern\mm tools\host-check\main.c kern\mm\best_fit_pmm.c kern\mm\buddy_pmm.c kern\mm\buddy_check.c /Fe:host-check.exe
host-check.exe
```

Assertions must remain enabled. Original Best-Fit framework tests and Buddy
behavior tests run first. Each allocator then receives 10000 deterministic
mixed operations, checking allocation ranges, pairwise non-overlap and final
free-page recovery. These do not replace the course grading script.
