#!/bin/sh
# Guest-only GDB run: drive ucore to the interesting memory accesses and let
# QEMU's -d mmu log record every TLB fill / page walk.
set -e

CODE_DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$CODE_DIR"

QEMU=${QEMU:-$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64}
GDB_GUEST=${GDB_GUEST:-riscv64-unknown-elf-gdb}
LOG_DIR=${LOG_DIR:-$CODE_DIR/../report/logs/gdb-b}
mkdir -p "$LOG_DIR"

rm -f "$LOG_DIR/mmu.log" "$LOG_DIR/guest-gdb.log" "$LOG_DIR/serial.log"

"$QEMU" -machine virt -display none -serial "file:$LOG_DIR/serial.log" \
    -monitor none -bios default -D "$LOG_DIR/mmu.log" -d mmu \
    -device loader,file=bin/ucore.img,addr=0x80200000 \
    -gdb tcp::43210 -S > "$LOG_DIR/qemu.log" 2>&1 &
QPID=$!
sleep 1

timeout 60 "$GDB_GUEST" -q -ex "cd $CODE_DIR" -x tools/gdb/guest.gdb \
    > "$LOG_DIR/guest-gdb.log" 2>&1 || true

sleep 1
kill "$QPID" 2>/dev/null || true
wait 2>/dev/null || true
echo "guest gdb + QEMU mmu logs written to $LOG_DIR"
