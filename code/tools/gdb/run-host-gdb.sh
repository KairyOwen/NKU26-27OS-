#!/bin/sh
# Host-only GDB run: attach to QEMU and log the emulated MMU's page walks
# while the kernel boots normally (no guest gdb attached).
set -e

CODE_DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$CODE_DIR"

QEMU=${QEMU:-$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64}
LOG_DIR=${LOG_DIR:-$CODE_DIR/../report/logs/gdb-b}
mkdir -p "$LOG_DIR"

rm -f "$LOG_DIR/host-gdb.log" "$LOG_DIR/qemu-host.log"

"$QEMU" -machine virt -display none -serial "file:$LOG_DIR/serial-host.log" \
    -monitor none -bios default \
    -device loader,file=bin/ucore.img,addr=0x80200000 \
    -gdb tcp::43210 -S > "$LOG_DIR/qemu-host.log" 2>&1 &
QPID=$!
sleep 1

# SIGINT lets gdb leave the target and flush its logging file.
timeout -s INT 25 gdb -batch -q "$QEMU" -p "$QPID" \
    -ex "set logging file $LOG_DIR/host-gdb.log" \
    -ex "set logging overwrite on" \
    -ex "set logging on" \
    -x tools/gdb/host.gdb < /dev/null > "$LOG_DIR/host-stdout.log" 2>&1 || true

kill "$QPID" 2>/dev/null || true
wait 2>/dev/null || true
echo "host gdb log written to $LOG_DIR/host-gdb.log"
