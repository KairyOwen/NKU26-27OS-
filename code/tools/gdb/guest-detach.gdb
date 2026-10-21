# Guest-side orchestration for the dual-GDB run:
#   1. run ucore to kern_entry and step until satp is enabled,
#   2. install a breakpoint at kern_init (virtual address, Sv39 active),
#   3. wait until the host gdb has attached and installed its breakpoints,
#   4. detach.  Detaching resumes QEMU, so the host gdb observes the
#      kern_init fetch and the memset data store from inside QEMU.
#
# This avoids two GDBs both issuing "continue" to the same gdbstub.
set pagination off
set confirm off

file bin/kernel
set arch riscv:rv64
target remote localhost:43210

break *0x80200000
continue
printf "\n=== GUEST: kern_entry reached (Bare mode) ===\n"
info registers pc sp satp

set $steps = 0
while $satp == 0 && $steps < 40
  stepi
  set $steps = $steps + 1
end
printf "=== GUEST: satp=0x%lx after %d stepi ===\n", $satp, $steps

# Sv39 is now enabled; this virtual-address breakpoint is translated by QEMU
# through the boot page table.
break kern_init
printf "=== GUEST: waiting for host gdb breakpoints ===\n"
shell rm -f /tmp/host_ready
shell touch /tmp/guest_ready
shell while [ ! -f /tmp/host_ready ]; do sleep 0.2; done

printf "=== GUEST: detaching, QEMU resumes under host gdb ===\n"
detach
quit
