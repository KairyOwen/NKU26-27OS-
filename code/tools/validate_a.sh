#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$src/../report/logs"
logs="$(cd "$src/../report/logs" && pwd)"
QEMU="${QEMU:-$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64}"
version="$("$QEMU" --version)"
[[ "$version" == 'QEMU emulator version 4.1.1'* ]] || { echo 'QEMU 4.1.1 required'; exit 1; }
if [[ "${1:-}" == env ]]; then
    { date -Is; uname -a; "$QEMU" --version; riscv64-unknown-elf-gcc --version;
      gdb-multiarch --version; make --version; } | tee "$logs/a-env.log"
    exit 0
fi
[[ "${1:-}" == check ]] || { echo 'Usage: bash tools/validate_a.sh env|check'; exit 1; }
stage="$(mktemp -d /tmp/lab4-a.XXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
cp -R "$src/." "$stage/"
cp "$src/tools/a_stage_init.c" "$stage/kern/init/init.c"
cd "$stage"
make clean
make KSRCDIR='kern/init kern/libs kern/debug kern/driver kern/trap kern/mm' 2>&1 | tee "$logs/a-build.log"
timeout --kill-after=3s 30s "$QEMU" -machine virt -nographic -bios default \
    -device loader,file=bin/ucore.img,addr=0x80200000 -monitor none </dev/null 2>&1 | tee "$logs/a-run.log"
! grep -Eqi 'kernel panic|assertion failed' "$logs/a-run.log"
grep -F '[A] same-page remap, permissions, idempotent remove, accounting: PASS' "$logs/a-run.log"
grep -F '[A] first/second page-table allocation failure rollback: PASS' "$logs/a-run.log"
grep -F '[A] 32-bit and compressed breakpoint return: PASS' "$logs/a-run.log"
grep -F '[A] physical memory, page tables and VMA: PASS' "$logs/a-run.log"
