# Guest-side orchestration for the "from reset" run:
# connect to the paused QEMU at the reset vector, wait for the host gdb to
# install its breakpoints, then detach so QEMU runs freely.  The host gdb
# then observes OpenSBI and the first S-mode fetch at kern_entry (Bare mode).
set pagination off
set confirm off

set arch riscv:rv64
target remote localhost:43210
printf "=== GUEST: connected at reset, pc=0x%lx ===\n", $pc

shell rm -f /tmp/host_ready
shell touch /tmp/guest_ready
shell while [ ! -f /tmp/host_ready ]; do sleep 0.2; done

printf "=== GUEST: detaching, QEMU starts from reset under host gdb ===\n"
detach
quit
