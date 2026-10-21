#!/bin/sh
# Dual-GDB orchestration:
#   guest gdb stops ucore at kern_entry / enables satp / installs kern_init
#   breakpoint, then waits; host gdb attaches, installs QEMU breakpoints and
#   continues; guest gdb detaches, which resumes QEMU; host gdb logs the walks.
set -e

CODE_DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$CODE_DIR"

QEMU=${QEMU:-$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64}
GDB_GUEST=${GDB_GUEST:-riscv64-unknown-elf-gdb}
LOG_DIR=${LOG_DIR:-$CODE_DIR/../report/logs/gdb-b}
mkdir -p "$LOG_DIR"
rm -f /tmp/host_ready /tmp/guest_ready

"$QEMU" -machine virt -display none -serial "file:$LOG_DIR/serial-dual.log" \
    -monitor none -bios default \
    -device loader,file=bin/ucore.img,addr=0x80200000 \
    -gdb tcp::43210 -S > "$LOG_DIR/qemu-dual.log" 2>&1 &
QPID=$!

sleep 1
"$GDB_GUEST" -batch -q -ex "cd $CODE_DIR" -x tools/gdb/guest-detach.gdb \
    < /dev/null > "$LOG_DIR/guest-gdb.log" 2>&1 &
GPID=$!

# Wait until the guest gdb has reached kern_entry and is waiting for us.
i=0
while [ ! -f /tmp/guest_ready ] && [ $i -lt 100 ]; do
    sleep 0.2
    i=$((i + 1))
done
if [ ! -f /tmp/guest_ready ]; then
    echo "guest gdb did not reach kern_entry" >&2
    kill "$QPID" "$GPID" 2>/dev/null || true
    exit 1
fi

gdb -batch -q "$QEMU" -p "$QPID" \
    -ex "set logging file $LOG_DIR/host-gdb.log" \
    -ex "set logging overwrite on" \
    -ex "set logging on" \
    -x tools/gdb/host.gdb < /dev/null > "$LOG_DIR/host-stdout.log" 2>&1 &
HPID=$!

wait "$GPID" || true
sleep 5
kill "$QPID" 2>/dev/null || true
sleep 1
kill "$HPID" 2>/dev/null || true
wait 2>/dev/null || true
echo "dual-GDB logs written to $LOG_DIR"
