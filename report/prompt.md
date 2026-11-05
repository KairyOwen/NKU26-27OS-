# Lab3 提示词与实现约束：A/B 阶段

记录范围：A 阶段（张哲宇）的基础迁移与同步分析；B 阶段（刘梓涵）的 Trap 入口与上下文恢复。C 后续补充中断异常处理与最终集成。

## 1. 实际需求记录

本次用户先要求分析并完成实验，报告遵循课程模板；随后明确 A → B → C 顺序接力，由 C 最终集成，并提出“那开始我的部分吧”。据此，本阶段实现范围限定为 A 的基础迁移、环境与交接材料，不提前完成 B/C 模块或填写完整实验成绩。

## 2. 本次实现 spec（协作约束整理）

以下是结合本次代码审阅形成的实现约束，用于复核和后续交接；不是虚构的历史逐字提问。

```text
在本次 lab3.zip 框架内迁移已有 Lab2 成果：
1. 只补 pmm.c 的 page_init 和 best_fit_pmm.c 的管理器实现，
   并将 init_pmm_manager 指向 Best-Fit。
2. pmm.c 中 alloc_pages/free_pages/nr_free_pages 已有中断保护，
   保留其原文；不能用旧 pmm.c 覆盖整个文件。
3. 核对 Lab3 当前宏定义，管理边界从 KERNBASE、KERNTOP、
   PHYSICAL_MEMORY_OFFSET 推导，不能直接使用缺失的旧宏。
4. 保留 DTB 校验、保留区、描述符容量检查、页对齐和无完整空闲页判断。
5. 不修改 Lab3 原始 Best-Fit 测试、评分脚本、Trap 帧结构和 SAVE_ALL；
   B/C 待完成的区域保留，注明阶段状态。
6. 为 A 阶段单独提供临时构建验证，正式启动路径保持原状；
   阶段测试不能冒充 make grade。
```

## 3. 本阶段关键问题与处理记录

### 新旧内存布局的兼容性

核对问题：Lab2 使用的 `PHYSICAL_MEMORY_END`、`KERNEL_BEGIN_PADDR` 在 Lab3 中不存在，是否应复制旧头文件？

采用处理：根据 Lab3 当前宏计算物理内核起点和管理末端，避免整体覆盖头文件或引入无关改动。它们当前对应 `0x80200000` 与 `0x88000000`，但计算依据保留在代码中。

### 迁移后中断状态的保持

核对问题：为什么不能把旧版内存分配包装函数一起搬过来？

采用处理：保留 Lab3 的保存/恢复 SIE 包装。临界区结束后恢复调用前的开关状态，而非无条件开中断；局部关中断与多核互斥、AMO 操作的作用分别解释。

### 顺序接力中的阶段验收

核对问题：B/C 的 Trap 尚未补齐，怎样验证 A 的内存管理而不改变最终框架？

采用处理：正式目录保留原入口和 Trap 空缺；验证脚本在临时副本替换 A 专用入口，并只在该次构建中排除 Trap 模块，运行内存自检和计数检查。阶段 PASS 与最终 100 分评分分开记录。

## 4. 已发生的核对与调试

- 静态对比确认原始文件只改动 `pmm.c` 和 `best_fit_pmm.c`。
- 比较并确认原始两个 Best-Fit 测试函数、同步头文件与中断保护包装未改。
- Windows 宿主适配测试运行迁移后的 Best-Fit 原始自检，计数恢复通过；此结果不覆盖 RISC-V AMO 或中断。
- 开发侧初次启动 MSVC 的命令引号处理失败，改用命令脚本后完成宿主测试。尚未发生的目标编译错误、Trap 调试和评分结果不作记录。
- 首次 Ubuntu 验证在链接时报错：原 `kmonitor` 引用了被排除的 Trap 模块中的 `print_trapframe`。修复限定在临时副本：保留原 panic 诊断，交互监视器替换为明确输出失败并停止的 A 测试端点，不改正式代码，不用空打印函数掩盖错误。用户随后完成重试，两张归档截图确认 QEMU 4.1.1 和 A 阶段 PASS。

## 5. 后续记录约定

B 已补充本文件第 6 节；C 补充中断异常处理、测试及最终迭代。可以把长对话归纳为关键问题和约束，但应标为整理记录，保留真实协作范围，不编造个人提问、模型版本或失败经历。

## 6. B 阶段：Trap 入口与上下文恢复

### 6.1 实际需求记录

本次用户提供 Lab3 三人分工文档，并指定 B（刘梓涵，2410683）负责模块一：在 A 已迁移内存管理的基础上，补齐 `kern/trap/trapentry.S` 中的 `RESTORE_ALL` 与 `__alltraps` 对 C 处理函数的调用。以下规格依据分工文档、`SAVE_ALL` 与 `struct trapframe` 整理，不是逐字聊天记录。

### 6.2 最终任务规格

```text
输入：Lab3 代码包中的 kern/trap/trapentry.S、kern/trap/trap.h；
      SAVE_ALL 已实现，struct trapframe 已定义；A 阶段已完成内存管理迁移。
任务：补齐 RESTORE_ALL 与 __alltraps 中的调用逻辑；保留 lab3 function1 标记，
      将 YOUR CODE 换成 2410683。
要求：
1. 保持 SAVE_ALL、struct trapframe、__alltraps/__trapret 边界不变。
2. 推导 36 个槽位：x0..x31 在 0..31，sstatus/sepc/badvaddr/scause 在 32..35，
   共 36*8=288 字节；288 为 16 的倍数，满足 ABI 栈对齐。
3. RESTORE_ALL：先用 s0/s1 从帧中读 sstatus/sepc 并 csrw；再恢复 x1、x3..x31；
   最后恢复 x2/sp，避免提前改变寻址基址。
4. 不恢复 scause/stval 等诊断 CSR；说明 sret 依据 sstatus.SPP/SPIE 与 sepc 返回。
5. __alltraps：mv a0, sp；jal trap；返回后 sp 不变并落入 __trapret。
6. 不修改 trap.c 的分发逻辑和 C 的处理函数；不修改 A 的内存管理代码。
判据：trapentry.S 汇编通过；槽位偏移与结构体一致；临时桩下 Test 1 的寄存器
      上下文检查通过；不把临时桩结果冒充最终 make grade。
```

### 6.3 关键决策与问题

- **CSR 恢复需要临时寄存器**：`csrw` 的源必须是通用寄存器，因此先把 `sstatus`/`sepc` 读入 s0/s1，再写 CSR；s0/s1 的原始值随后从帧槽位 8/9 恢复，不会丢失。
- **sp 最后恢复**：所有帧槽位都相对 sp 寻址，提前恢复 x2 会导致后续 `ld` 偏移错位。
- **不恢复 scause/stval**：它们是诊断信息；返回 PC 和特权级分别由 `sepc` 与 `sstatus.SPP` 控制，`sret` 还会令 `SIE=SPIE`、`SPIE=1`、`SPP=0`。
- **工具链兼容**：本机 binutils 2.47 不再识别 RISC-V 1.9 旧名 `sbadaddr`（1.10 起为 `stval`，0x143）。为保持 SAVE_ALL 原文不变，在文件开头加 `.equ sbadaddr, 0x143`；旧工具链即使仍支持旧名也不改变语义。
- **EPC 前移按指令长度**：临时桩初版对断点统一 `epc += 4` 导致 Test 1 FAIL；objdump 显示 `ebreak` 被汇编为 2 字节 `c.ebreak`（`9002`），改为 `+2` 后通过。正式处理函数必须判断 16/32 位指令，不能统一 `+4`。

### 6.4 验证记录（实际发生）

- `riscv64-unknown-elf-gcc -mcmodel=medany -std=gnu99 -Werror -nostdinc -Ilibs -Ikern/trap -c kern/trap/trapentry.S` 通过。
- 反汇编确认 `__trapret`：`ld s0,256(sp)`、`ld s1,264(sp)`、`csrw sstatus,s0`、`csrw sepc,s1`、恢复 GPR、最后 `ld sp,16(sp)`、`sret`。
- 临时桩（不进入仓库的 `~/lab3-b-test`，trap.c 使用临时处理函数）运行注入的 Test 1：
  `[Test 1] Trap entry and breakpoint return: PASS (35/35)`。
- 临时桩运行不是最终 `make grade`；Test 2/3 与 100 分评分待 C 完成处理函数后统一验证。日志见 `report/logs/b-stage-context-stub.log` 与 `b-stage-assembly-check.log`。

### 6.5 交接 C

C 需要实现 `interrupt_handler`/`exception_handler`，处理时钟、非法指令、断点及其他兜底输出；正式实现 EPC 前移时按指令长度解码；完成时钟重设、ticks、100 ticks 与关机条件。集成后运行正式 `make grade`，并在报告中明确区分 B 的临时桩结果与 C 的正式评分。
