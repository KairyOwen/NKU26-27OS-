# Guest-side GDB script: connect to the QEMU gdbstub and drive the ucore
# kernel to the memory accesses that the host-side GDB script observes.
#
# Usage (inside the lab2 code directory):
#   riscv64-unknown-elf-gdb -q -x tools/gdb/guest.gdb
#
# Note: before satp is written the CPU is in Bare mode, so a physical address
# is also a valid virtual address.  entry.S starts at PA 0x80200000, i.e. the
# direct-map VA 0xffffffffc0200000.  kern_init is installed by symbol after
# Sv39 is enabled; in the current lab2 build it is linked at VA
# 0xffffffffc02000d6 (PA 0x802000d6).
set pagination off
set confirm off

file bin/kernel
set arch riscv:rv64
# 1234 is occupied by Weixin on this machine, so the QEMU gdbstub uses 43210.
target remote localhost:43210

break *0x80200000
continue
printf "\n=== GUEST: kern_entry reached (Bare mode, satp not written yet) ===\n"
info registers pc sp satp
x/6i $pc

# Step through entry.S until satp has been written and sfence.vma executed.
# Only then can a virtual-address breakpoint be translated correctly.
set $steps = 0
while $satp == 0 && $steps < 40
  stepi
  set $steps = $steps + 1
end
printf "\n=== GUEST: satp written after %d stepi ===\n", $steps
info registers pc satp
# After satp is written, $pc is still a physical address (execution continues
# at PA until the first virtual jump); add the direct-map offset
# 0xffffffff40000000 to disassemble the same bytes via their VA.
x/2i ((unsigned long)$pc + 0xffffffff40000000)

# pre-insert the breakpoint at kern_init's virtual address (paging is on)
break kern_init

continue
printf "\n=== GUEST: kern_init reached (Sv39 enabled) ===\n"
info registers pc sp satp
# PTE[511] of the boot page table maps the 1 GiB direct-map region.  In the
# current lab2 build boot_page_table_sv39 is at VA 0xffffffffc0205000, so
# PTE[511] (base + 511 * 8 = +0xff8) lives at VA 0xffffffffc0205ff8.
printf "boot_page_table_sv39[511] at VA 0xffffffffc0205ff8:\n"
x/gx 0xffffffffc0205ff8
printf "satp=0x%lx  PPN=0x%lx\n", $satp, ($satp & 0xfffffffffff)

break memset
continue
printf "\n=== GUEST: memset entry (about to store to edata) ===\n"
info registers a0 a1 a2 pc
x/6i $pc

break pmm_init
continue
printf "\n=== GUEST: pmm_init reached; earlier accesses used Sv39 ===\n"
info registers pc sp satp

detach
quit
