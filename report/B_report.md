# 操作系统实验报告：B 阶段章节（模块一：Trap 上下文恢复与入口）

> 本文是交给 C 合并的 B 阶段材料，沿用课程模板的章节结构；A 阶段内容见 `A_report.md`，C 完成中断异常处理与最终验收后补齐其余章节。
> 文中结论均来自本次实际汇编检查与临时桩运行；未完成的评分项明确标注为待 C 验证，不写成已通过。

## 实验基本信息

| 项目 | 内容 |
|---|---|
| 实验名称 | Lab3：中断与异常处理 |
| 小组成员 | 2412101-张哲宇、2410683-刘梓涵、2411310-李熔吉 |
| 本阶段负责人 | B：2410683-刘梓涵 |
| 阶段完成日期 | 2026-11-04；完整实验完成日期由 C 验收后填写 |

### 小组分工（B 部分）

A 先完成 Lab2 内存管理迁移、Best-Fit 接入、环境与阶段验证，交 B；B 在 A 版本上实现 Trap 上下文恢复与入口，交 C；C 实现中断/异常处理函数并完成最终集成、评分和报告合并，最后由 A 审核提交。完整分工见随包的 `分工.md`。

## 一、实验目的（B 部分）

1. 理解 RISC-V Trap 发生时硬件自动保存的 CSR 与软件需要保存的通用寄存器。
2. 根据既有 `SAVE_ALL` 与 `struct trapframe` 推导 36 个槽位的布局，完成 `RESTORE_ALL`。
3. 在 `__alltraps` 中把 trapframe 指针传给 C 处理函数，并保证返回后能正确执行 `__trapret` 与 `sret`。
4. 区分配置返回控制状态的 CSR（`sstatus`、`sepc`）与只用于诊断的 CSR（`scause`、`stval`），说明恢复顺序与栈对齐约束。

## 二、实验环境（B 阶段）

B 阶段在本机 WSL 环境复现 A 的 Lab3 基线；A 阶段报告记录的另一台机器的 GCC 版本不同，但 QEMU 均为课程要求的 4.1.1。

| 项目 | 实际环境 |
|---|---|
| 宿主与 Linux | Windows + WSL 2，Ubuntu 26.04 LTS，内核 6.18.33.2-microsoft-standard-WSL2 |
| QEMU | 4.1.1，源码编译（`$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64`） |
| 交叉编译器 | riscv64-unknown-elf-gcc 16.1.0（binutils 2.47） |
| 调试器 | 宿主 gdb 17.1；客体 riscv64-unknown-elf-gdb 17.2 |
| Make / Python | GNU Make 4.4.1 / Python 3.14.4 |

| 成员 | AI 编程工具 | 底层模型 | 备注 |
|---|---|---|---|
| 刘梓涵 | DeepSeek Harness | DeepSeek-V4.1-Flash | 辅助分析、代码生成与本地验证；结论均以汇编/运行输出复核 |

## 三、实验整体逻辑分析（B 部分）

本实验的 Trap 链为：

```text
idt_init 设置 stvec 与 sscratch
  -> 硬件在 Trap 时更新 sepc/sstatus/scause/stval 等 CSR
  -> stvec -> __alltraps -> SAVE_ALL 构造 36 槽 trapframe
  -> a0 = trapframe 指针，调用 trap(tf)
  -> trap_dispatch 按 scause 分发到 interrupt_handler 或 exception_handler（C 实现）
  -> trap 返回 -> __trapret -> RESTORE_ALL
  -> sret 按 sstatus.SPP/SPIE/SIE 与 sepc 返回原执行流
```

B 负责其中“保存之后”的入口调用与“返回之前”的上下文恢复；中间的分发和处理函数由 C 完成。因此 B 阶段可以在 C 的处理函数空缺时先做汇编静态检查，并用临时桩验证入口/恢复路径，但不能把临时桩结果当作完整评分。

## 四、实验内容与实现

### 模块一：Trap 上下文恢复与入口

**负责人：** 2410683-刘梓涵

#### 模块功能描述

涉及文件：

- `kern/trap/trapentry.S`：`SAVE_ALL` 已由框架给出；本阶段补 `RESTORE_ALL` 与 `__alltraps` 到 C 的调用。
- `kern/trap/trap.h`：`struct pushregs` 与 `struct trapframe` 的槽位定义；本阶段不修改。
- `kern/trap/trap.c`：`trap()`/`trap_dispatch()` 已存在；其调用的两个处理函数由 C 实现。

`struct trapframe` 共 36 个 8 字节槽位，合计 288 字节；288 是 16 的倍数，因此 `addi sp, sp, -288` 不会破坏 RISC-V ABI 的 16 字节栈对齐要求。

| 槽位 | 内容 | 槽位 | 内容 |
|---|---|---|---|
| 0 | x0/zero | 18–27 | s2–s11 |
| 1 | x1/ra | 28–31 | t3–t6 |
| 2 | x2/sp（原始栈顶） | 32 | sstatus |
| 3 | x3/gp | 33 | sepc |
| 4 | x4/tp | 34 | sbadaddr/stval |
| 5–7 | t0–t2 | 35 | scause |
| 8–9 | s0–s1 | | |
| 10–17 | a0–a7 | | |

`SAVE_ALL` 的关键点（原文保持，不修改）：

1. 先用 `csrw sscratch, sp` 暂存原 sp，再一次性减 288 字节分配 trapframe。
2. 保存 x0、x1、x3～x31；x2 不直接存，而是稍后通过 `csrrw s0, sscratch, x0` 取出原 sp，写入槽位 2。
3. 用 s1～s4 暂存 `sstatus/sepc/sbadaddr/scause`，分别写入槽位 32～35。
4. `sscratch` 被写为 0，用于之后判断 Trap 是否来自内核（本实验不涉及用户态栈切换）。

`RESTORE_ALL` 的恢复顺序：

1. 用 `LOAD s0, 32*REGBYTES(sp)` 与 `LOAD s1, 33*REGBYTES(sp)` 取出 `sstatus/sepc`；
2. 立即 `csrw sstatus, s0`、`csrw sepc, s1`；
3. 恢复 x1、x3～x31（x0 恒为 0，无需恢复）；
4. **最后**恢复 x2/sp，因为前面所有槽位都相对 sp 寻址，提前改 sp 会读错 trapframe；
5. 落入 `__trapret` 执行 `sret`。

为什么用 s0/s1 作临时寄存器：CSR 写指令的源操作数必须是通用寄存器，而 trapframe 在内存中；先读入通用寄存器再 `csrw`。s0/s1 的原始值在下一步会从 trapframe 的槽位 8/9 恢复，因此不会丢失。

为什么最后恢复 sp：`SAVE_ALL` 保存的是“分配 trapframe 之前的 sp”；恢复它之后就不能再相对 sp 访问 trapframe，因此必须作为最后一步。

为什么不恢复 `scause`/`stval`：这两个是 Trap 原因和地址的诊断信息，不属于返回控制状态；返回由 `sstatus`（SPP/SPIE/SIE 等）和 `sepc` 决定。`sret` 会把 PC 设为 `sepc`，把特权级设为 `sstatus.SPP`，并令 `SIE = SPIE`、`SPIE = 1`、`SPP = 0`。本实验主要返回 S 态，不能笼统说每次 `sret` 都回 U 态。

`__alltraps` 的调用逻辑：

```asm
SAVE_ALL
mv a0, sp        # trap(struct trapframe *tf)，tf 指向刚保存的帧
jal trap
# 从 trap 返回后 sp 仍指向同一 trapframe
# 落入 __trapret -> RESTORE_ALL -> sret
```

`jal trap` 会改写 x1/ra，但 SAVE_ALL 已把原 x1 存入槽位 1，RESTORE_ALL 会从帧中恢复，因此不影响原执行流。

#### 最终提示词

以下为根据本次实际开发整理的任务规格，用于复核与交接；不是逐字聊天记录。

```text
输入：Lab3 代码包中的 kern/trap/trapentry.S、kern/trap/trap.h；其中 SAVE_ALL
      已实现，struct trapframe 已定义；A 阶段已完成 Lab2 内存管理迁移。
任务：补齐 trapentry.S 的 RESTORE_ALL 与 __alltraps 中的调用逻辑。
要求：
1. 保持 SAVE_ALL、struct trapframe 和 __alltraps/__trapret 的函数边界不变；
   只填写标有 lab3 function1 的区域，并把 YOUR CODE 换成 2410683。
2. 根据 SAVE_ALL 与 trapframe 字段推导 36 个槽位：x0..x31 在 0..31，
   sstatus/sepc/badvaddr/scause 在 32..35，共 288 字节。
3. RESTORE_ALL 先用临时通用寄存器从帧中恢复 sstatus、sepc 并写 CSR；
   再恢复 x1、x3..x31；最后恢复 x2/sp，避免提前改变栈基址。
4. 不恢复 scause/stval 等诊断 CSR；说明 sret 依据 sstatus.SPP 与
   sstatus.SPIE、sepc 完成返回。
5. __alltraps 中把当前 sp 放入 a0 调用 trap(tf)；返回后 sp 不变，
   继续落入 __trapret。
6. 不修改 trap.c 的分发逻辑和 C 的处理函数；它们由 C 阶段实现。
判据：汇编通过；槽位偏移与结构体一致；临时桩下 Test 1 的寄存器上下文
      检查通过；不把临时桩结果冒充最终 make grade。
```

#### 实现迭代过程

**第 1 次迭代：按 SAVE_ALL 反推恢复顺序。**
先列出 36 个槽位与每个槽位的保存来源，再写 `RESTORE_ALL`。初版重点是两个约束：

- CSR 不能直接从内存写：需要先用 s0/s1 读入 `sstatus/sepc`，再 `csrw`；
- x2/sp 必须最后恢复：其余 35 个槽位都以 sp 为基址，提前恢复 sp 会使后续读取全部错位。

按此顺序实现后，汇编通过；`objdump` 确认 `csrw sstatus`、`csrw sepc` 出现在 GPR 恢复之前，`ld sp, 16(sp)` 出现在最后。

**第 2 次迭代：处理工具链的旧 CSR 名称。**
本机 `riscv64-unknown-elf-gcc 16.1.0`（binutils 2.47）的汇编器不再识别 SAVE_ALL 中的旧名 `sbadaddr`（RISC-V 1.9 名称），报错 `unknown CSR 'sbadaddr'`。由于 B 阶段不应改写 SAVE_ALL，在文件开头增加数值别名：

```asm
.equ sbadaddr, 0x143   # 1.10 起该 CSR 名为 stval
```

这样 SAVE_ALL 文本保持原样，汇编器把 `sbadaddr` 解析为 0x143。旧工具链即使仍支持 `sbadaddr`，该别名也不改变语义；最终使用哪套工具链由 C/A 在统一环境中确认。

**第 3 次迭代：用临时桩验证入口与恢复路径。**
C 的两个处理函数尚未实现，正式内核不能完整链接，因此在一份**不进入仓库**的临时副本（`~/lab3-b-test`）中：

- 保留 B 的 `trapentry.S`；
- 在 `trap.c` 的 `lab3 function2` 位置放临时桩：`interrupt_handler` 为空，`exception_handler` 对断点异常执行 `tf->epc += 2`（后续由 C 替换为正式处理）；
- 用 `tools/inject.py` 注入 Test 1，`make DEFS+=-DGRADE_LAB3_CONTEXT` 构建并运行 QEMU 4.1.1。

第一次临时运行得到 `[Test 1] ... FAIL (register context)`。排查发现不是 `RESTORE_ALL` 的问题：`test_lab3_context.S` 中的 `ebreak` 被汇编成 2 字节的压缩指令 `c.ebreak`（objdump 显示 `9002 ebreak`），而临时桩按 4 字节执行 `epc += 4`，跳过了下一条指令，导致寄存器检查错位；改为 `+2` 后得到 `[Test 1] Trap entry and breakpoint return: PASS (35/35)`。这条记录作为给 C 的提醒：正式处理函数必须按指令实际长度（16/32 位）更新 EPC，不能统一 `+4`。

#### 验证与证据

1. **汇编检查**：`riscv64-unknown-elf-gcc -mcmodel=medany -std=gnu99 -Werror -nostdinc -Ilibs -Ikern/trap -c kern/trap/trapentry.S` 通过（exit 0）。
2. **反汇编核对**：
   - `__alltraps` 开始：`csrw sscratch,sp`、`addi sp,sp,-288`；
   - `__trapret`：`ld s0,256(sp)`、`ld s1,264(sp)`、`csrw sstatus,s0`、`csrw sepc,s1`，随后恢复 GPR，最后 `ld sp,16(sp)`、`sret`；
   - 槽位 32/33/2 的偏移分别为 256/264/16，与 trapframe 结构体一致。
3. **临时桩运行**：Test 1 通过 35/35，日志见 `report/logs/b-stage-context-stub.log`；该运行使用临时桩处理函数，**不是最终 make grade**，Test 2/3 仍待 C。
4. **完整构建/评分**：当前不执行 `make grade`。C 的 `interrupt_handler`/`exception_handler` 未实现时，正式内核不能完整链接，这是阶段分工的正常状态，不通过删除调用或空实现绕过。

| 检查项 | 结果 | 能证明什么 |
|---|---|---|
| 汇编通过 | 通过 | trapentry.S 语法、宏展开、CSR 名称在目标工具链可用 |
| 槽位/偏移核对 | 通过 | RESTORE_ALL 读取的偏移与 struct trapframe 一致 |
| 临时桩 Test 1 | PASS (35/35) | 入口传参、RESTORE_ALL 恢复 GPR/sp 并 sret 返回的路径可行 |
| 正式 make grade | 未执行 | C 的处理函数尚未实现；不能提前声称评分通过 |

#### 交接给 C

- 新增/修改：`code/kern/trap/trapentry.S`（RESTORE_ALL、__alltraps、sbadaddr 兼容别名）。
- 未修改：`SAVE_ALL`、`struct trapframe`、`trap.c` 分发逻辑、A 的内存管理代码。
- C 需要实现：`kern/trap/trap.c` 中的 `interrupt_handler`/`exception_handler`；断点与非法指令的 EPC 前移必须按 16/32 位指令长度解码（B 的临时桩先用 +2 验证了压缩 ebreak）；时钟重设、ticks、100 ticks、关机条件按分工文档实现。
- C 集成后运行正式 `make grade`（QEMU 4.1.1），并把 Test 1 结果与 B 的临时桩结果区分记录。

## 五、测试与验证（B 阶段）

B 阶段只验证与模块一直接相关的性质，不把 A 的内存测试或临时桩结果混入最终评分：

- `report/logs/b-stage-assembly-check.log`：汇编命令、GCC 版本与 `__alltraps`/`__trapret` 关键反汇编。
- `report/logs/b-stage-context-stub.log`：临时桩构建后的 QEMU 串口输出，含 `[Test 1] ... PASS (35/35)`。
- `report/logs/b-stage-context-stub-build.log`：临时桩构建日志（仅在临时副本中使用，未提交桩代码）。
- 正式 `make grade` 的 Test 1/2/3 由 C 在完整实现后统一运行；B 不声称当前已取得 100 分。

## 六、实验总结（B 部分）

1. Trap 上下文不是普通函数调用的保存集合：除了 callee/caller-saved 寄存器，还必须保存全部通用寄存器、`sstatus` 与 `sepc`，否则返回后执行流和特权状态都可能改变。
2. `sret` 的返回目标由 `sepc` 决定，返回特权级由 `sstatus.SPP` 决定；`SIE/SPIE` 的恢复顺序与中断使能相关。
3. 恢复顺序由寻址方式决定：所有槽位相对 sp，因此 sp 最后恢复；CSR 需临时寄存器中转，临时寄存器的原值必须从帧中恢复。
4. 框架已有 `SAVE_ALL` 是布局的唯一依据；B 只补恢复与调用，不改变帧格式，避免破坏 A/C 的接口约定。
5. 工具链版本会影响汇编可接受的 CSR 名称与压缩指令编码；阶段验证必须针对实际工具链，不能照抄旧环境的结论。
