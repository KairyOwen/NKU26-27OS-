#!/bin/sh
# Dual-GDB demo driver: host gdb debugs QEMU itself, guest gdb debugs ucore.
#
# Run inside WSL from the lab2 code directory:  sh tools/gdb/run-dual-gdb.sh
set -e

CODE_DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$CODE_DIR"

QEMU=${QEMU:-$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64}
GDB_GUEST=${GDB_GUEST:-riscv64-unknown-elf-gdb}
LOG_DIR=${LOG_DIR:-$CODE_DIR/../report/logs/gdb-b}
mkdir -p "$LOG_DIR"
rm -f /tmp/host_ready /tmp/guest_at_entry

echo "[1/4] start QEMU 4.1.1 (debug build) with -s -S"
"$QEMU" -machine virt -display none -serial "file:$LOG_DIR/serial.log" \
    -monitor none -bios default -D "$LOG_DIR/qemu-mmu.log" -d mmu \
    -device loader,file=bin/ucore.img,addr=0x80200000 \
    -gdb tcp::43210 -S > "$LOG_DIR/qemu.log" 2>&1 &
QPID=$!
sleep 2
echo "    QEMU pid=$QPID"

echo "[2/4] host gdb attaches to the QEMU process (background)"
gdb -batch -q "$QEMU" -p "$QPID" \
    -ex "set logging file $LOG_DIR/host-gdb.log" \
    -ex "set logging overwrite on" \
    -ex "set logging on" \
    -x tools/gdb/host.gdb < /dev/null > "$LOG_DIR/host-stdout.log" 2>&1 &
HPID=$!
sleep 8

echo "[3/4] guest gdb drives the ucore kernel"
timeout 60 "$GDB_GUEST" -batch -q -ex "cd $CODE_DIR" -x tools/gdb/guest.gdb \
    < /dev/null > "$LOG_DIR/guest-gdb.log" 2>&1 || true

echo "[4/4] stop QEMU and host gdb"
kill "$QPID" 2>/dev/null || true
sleep 1
kill "$HPID" 2>/dev/null || true
wait 2>/dev/null || true

echo "logs written to $LOG_DIR"
