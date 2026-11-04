#!/usr/bin/env bash
set -euo pipefail
code_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$code_dir/../report/logs"
logs="$(cd "$code_dir/../report/logs" && pwd)"

if [[ -z "${QEMU:-}" ]]; then
    QEMU="$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64"
fi
if [[ ! -x "$QEMU" ]]; then
    echo 'Set QEMU to the executable built from QEMU 4.1.1 sources.' >&2
    exit 1
fi
qemu_version="$("$QEMU" --version)"
if [[ "$qemu_version" != 'QEMU emulator version 4.1.1'* ]]; then
    echo "Expected QEMU 4.1.1, got: $qemu_version" >&2
    exit 1
fi

case "${1:-help}" in
    env)
        {
            date -Is
            uname -a
            printf 'QEMU executable: %s\n' "$QEMU"
            "$QEMU" --version | sed -n '1p'
            riscv64-unknown-elf-gcc --version | sed -n '1p'
            gdb-multiarch --version | sed -n '1p'
            make --version | sed -n '1p'
            python3 --version
        } | tee "$logs/a-environment.log"
        ;;
    check)
        stage_dir="$(mktemp -d /tmp/lab3-a-check.XXXXXX)"
        trap 'rm -rf -- "$stage_dir"' EXIT
        mkdir -p "$stage_dir/code"
        cp -R "$code_dir/." "$stage_dir/code/"
        cp "$code_dir/tools/a_stage_init.c" "$stage_dir/code/kern/init/init.c"
        # panic.c retains diagnostics, then stops here instead of using Trap printing.
        cp "$code_dir/tools/a_stage_monitor.c" "$stage_dir/code/kern/debug/kmonitor.c"
        cd "$stage_dir/code"
        make clean 2>&1 | tee "$logs/a-build.log"
        # Exclude the unfinished B/C Trap module in this temporary build only.
        make KSRCDIR='kern/init kern/libs kern/debug kern/driver kern/mm' \
            2>&1 | tee -a "$logs/a-build.log"
        timeout --kill-after=3s 20s "$QEMU" \
            -machine virt -nographic -bios default \
            -device loader,file=bin/ucore.img,addr=0x80200000 \
            -monitor none </dev/null 2>&1 | tee "$logs/a-boot.log"
        if grep -Eqi 'kernel panic|assertion failed' "$logs/a-boot.log"; then
            echo 'A-stage kernel failure; inspect a-boot.log.' >&2
            exit 1
        fi
        grep -F 'memory management: best_fit_pmm_manager' "$logs/a-boot.log"
        grep -F 'check_alloc_page() succeeded!' "$logs/a-boot.log"
        grep -F '[A stage] allocation/accounting and disabled SIE preserved: PASS' "$logs/a-boot.log"
        grep -F '[A stage] PASS; Trap and timer tests remain for B/C' "$logs/a-boot.log"
        ;;
    *)
        echo 'Usage: bash tools/validate_a.sh env|check'
        echo 'check builds a temporary A-only kernel; it is not make grade.'
        ;;
esac
