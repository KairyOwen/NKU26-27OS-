# Lab3 B 阶段交接说明

负责人：刘梓涵（2410683）；交接对象：C 李熔吉（2411310）；最终由 A 张哲宇审核提交。

## 已准备的内容

- `code/kern/trap/trapentry.S`：补齐 `RESTORE_ALL` 与 `__alltraps` 中的调用逻辑，保留 `SAVE_ALL`、`struct trapframe` 与 `__trapret` 边界。
- `code/kern/trap/trapentry.S` 开头新增 `sbadaddr` 数值别名（`0x143`，即 `stval`），用于兼容不再识别旧 CSR 名的新版 binutils；`SAVE_ALL` 原文未改。
- `report/B_report.md`：B 阶段章节（模块一的功能、spec、提示词、迭代、验证与交接）。
- `report/logs/b-stage-assembly-check.log`：汇编与 `__alltraps`/`__trapret` 反汇编证据。
- `report/logs/b-stage-context-stub.log`、`b-stage-context-stub-build.log`：临时桩构建与 Test 1 运行日志。
- `report/prompt.md`：追加 B 阶段实际任务规格与验证记录，C 继续补充并合并。
- `.gitignore`：补上 `code/bin/`、`code/obj/` 等构建产物忽略规则（A 阶段原分支缺失该文件）。
- `.gitattributes`：补充与 Lab1/Lab2 一致的 LF 行尾规则（A 阶段原分支缺失该文件）。

未修改：`SAVE_ALL`、`struct trapframe`、`trap.c` 的 `trap()`/`trap_dispatch()`、A 阶段的 `pmm.c`/`best_fit_pmm.c`/Makefile/评分工具。

## 当前验证结论

1. `trapentry.S` 可单独汇编通过（riscv64-unknown-elf-gcc 16.1.0，binutils 2.47）。
2. 反汇编确认 `__trapret` 的恢复顺序：
   - `ld s0, 256(sp)` / `ld s1, 264(sp)` 读 `sstatus`/`sepc`；
   - `csrw sstatus, s0` / `csrw sepc, s1`；
   - 恢复 x1、x3～x31；
   - 最后 `ld sp, 16(sp)`；
   - `sret`。
3. `__alltraps` 中 `mv a0, sp` + `jal trap`，调用返回后落入 `__trapret`。
4. 在**不进入仓库**的临时副本 `~/lab3-b-test` 中，用临时桩处理函数（断点异常 `epc += 2`）运行注入的 Test 1，得到：
   `[Test 1] Trap entry and breakpoint return: PASS (35/35)`。
   该结果只证明入口/恢复路径，不是最终 `make grade`；正式评分待 C。

## 重要注意事项

1. **`sbadaddr` 兼容**：本机 binutils 2.47 不识别 `sbadaddr`（RISC-V 1.9 旧名）；已用 `.equ sbadaddr, 0x143` 保持 `SAVE_ALL` 原文。若 C/A 使用仍识别旧名的旧工具链，该别名也不会改变语义；如统一更换工具链，先确认汇编仍通过。
2. **EPC 前移必须按指令长度**：临时桩第一版按 `+4` 前移，导致 Test 1 FAIL；objdump 显示 `ebreak` 被汇编为 2 字节 `c.ebreak`（`9002`），改为 `+2` 后 PASS。C 的正式处理函数必须根据指令编码判断 16/32 位，不能统一 `+4`，也不能假设 `ebreak` 一定是 32 位。
3. **不要恢复 `scause`/`stval`**：它们是诊断信息；返回由 `sstatus` 与 `sepc` 控制。`sret` 的特权级由 `sstatus.SPP` 决定，本实验主要返回 S 态。
4. **sp 最后恢复**：trapframe 所有槽位以 sp 为基址，提前恢复 x2 会读错后续槽位。
5. **临时桩代码不在仓库**：`~/lab3-b-test` 只用于本地验证；正式 `trap.c` 的两个处理函数由 C 实现，不能提交空实现或删除调用。

## 给 C 的继续开发要求

1. 实现 `kern/trap/trap.c` 的 `interrupt_handler()` 与 `exception_handler()`，保留 `trap()`/`trap_dispatch()` 和已有打印函数。
2. 处理时钟中断 `IRQ_S_TIMER`：`clock_set_next_event()`、`ticks` 累加、每 100 次输出 `100 ticks`、达到关机阈值调用 `sbi_shutdown()`。
3. 处理非法指令与断点异常：输出 `Illegal instruction at`、`Breakpoint at` 等要求信息；按实际指令长度更新 EPC；时钟中断不移动 EPC。
4. 在 A/B 代码基础上干净构建，用 QEMU 4.1.1 运行正式 `make grade`，三项评分全部通过后再合并报告。
5. 合并时保留 B 的 `B_report.md` 章节与 `prompt.md` 追加内容，不覆盖 A 的迁移说明；报告最终环境表由 C 统一（A 与 B 的 GCC 版本不同，但 QEMU 均为 4.1.1）。

## 复现命令

```bash
cd /mnt/d/document/OS/NKU26-27OS-/code
export PATH=$HOME/riscv/bin:$PATH
riscv64-unknown-elf-gcc -mcmodel=medany -std=gnu99 -Werror -nostdinc \
  -Ilibs -Ikern/trap -c kern/trap/trapentry.S -o /tmp/trapentry.o
```

临时桩验证（仅参考，不要在正式目录执行）：

```bash
# 前提：~/lab3-b-test 为代码副本，trap.c 中有临时桩，已运行 inject.py
cd ~/lab3-b-test
make clean && make DEFS+=-DGRADE_LAB3_CONTEXT -j4
timeout -s KILL 8s "$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64" \
  -machine virt -display none -serial file:/tmp/b-test.out -monitor none \
  -bios default -device loader,file=bin/ucore.img,addr=0x80200000
grep "Test 1" /tmp/b-test.out
```

正式评分（C 完成处理函数后）：

```bash
cd /mnt/d/document/OS/NKU26-27OS-/code
make QEMU="$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64" grade
```
