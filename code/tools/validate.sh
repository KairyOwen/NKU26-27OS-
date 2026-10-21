#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p ../report/logs
logs="$(cd ../report/logs && pwd)"

if [[ -z "${QEMU:-}" ]]; then
    if [[ -x "$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64" ]]; then
        QEMU="$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64"
    elif [[ -x "$HOME/src/qemu-4.1.1-build/riscv64-softmmu/qemu-system-riscv64" ]]; then
        QEMU="$HOME/src/qemu-4.1.1-build/riscv64-softmmu/qemu-system-riscv64"
    else
        QEMU="$(command -v qemu-system-riscv64 || true)"
    fi
fi
if [[ -z "$QEMU" || ! -x "$QEMU" ]]; then
    echo 'QEMU executable not found. Set QEMU=/path/to/qemu-system-riscv64.' >&2
    exit 1
fi
version="$($QEMU --version | head -n 1)"
if [[ "$version" != 'QEMU emulator version 4.1.1'* ]]; then
    echo "Expected QEMU 4.1.1, found: $version" >&2
    exit 1
fi

run_kernel() {
    local mode="$1" logfile="$2" result
    make clean
    make PMM="$mode" 2>&1 | tee "${logfile%.log}-build.log"
    set +e
    timeout --kill-after=3s 30s "$QEMU" -machine virt -nographic -bios default \
        -device loader,file=bin/ucore.img,addr=0x80200000 </dev/null 2>&1 | tee "$logfile"
    result=${PIPESTATUS[0]}
    set -e
    if [[ "$result" != 0 && "$result" != 124 && "$result" != 137 ]]; then
        echo "Unexpected run exit: $result" >&2
        exit 1
    fi
    if grep -Eqi 'kernel panic|assertion failed|failed assertion' "$logfile"; then
        echo 'Kernel failure detected; inspect the log.' >&2
        exit 1
    fi
    grep -F 'check_alloc_page() succeeded!' "$logfile"
}

case "${1:-help}" in
    env)
        {
            date -Is
            uname -a
            printf 'QEMU executable: %s\n' "$QEMU"
            "$QEMU" --version | head -n 1
            riscv64-unknown-elf-gcc --version | head -n 1
            gdb-multiarch --version | head -n 1
            make --version | head -n 1
            python3 --version
            command -v bc
        } | tee "$logs/environment.log"
        ;;
    best-fit)
        run_kernel best_fit "$logs/best-fit.log"
        grep -F 'memory management: best_fit_pmm_manager' "$logs/best-fit.log"
        ;;
    grade)
        command -v bc >/dev/null
        make PMM=best_fit QEMU="$QEMU" GDB=gdb-multiarch grade 2>&1 | tee "$logs/grade.log"
        grep -F 'Total Score: 20/20' "$logs/grade.log"
        ;;
    buddy)
        run_kernel buddy "$logs/buddy.log"
        grep -F '[Buddy] ALL TESTS PASSED' "$logs/buddy.log"
        ;;
    restore)
        make clean
        make PMM=best_fit
        echo 'Default Best-Fit image rebuilt. Ready for GDB.'
        ;;
    *)
        echo 'Usage: bash tools/validate.sh {env|best-fit|grade|buddy|restore}'
        ;;
esac
