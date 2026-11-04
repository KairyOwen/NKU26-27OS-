# Lab3 A 阶段交接说明

负责人：张哲宇（2412101）；交接对象：B 刘梓涵，后续由 C 李熔吉完成最终集成。

## 已准备的内容

- `code/kern/mm/pmm.c`：补齐 `page_init()`，默认选中 Best-Fit，保留 Lab3 三个接口的中断保护。
- `code/kern/mm/best_fit_pmm.c`：迁移已完成的管理器，保留本次原始两个测试函数。
- `code/tools/validate_a.sh`、`a_stage_init.c` 与 `a_stage_monitor.c`：独立 A 阶段测试，只在临时目录构建使用；测试监视器遇错后停止，不依赖未完成的 Trap 打印。
- `report/A_report.md`：按课程模板组织的本人章节，供 C 合并进最终 `report.md`。
- `report/prompt.md`：A 阶段的实际需求与实现约束整理，B/C 后续追加。
- `report/logs/a-static-check.log`、`a-native-best-fit.log`：已取得的开发侧验证证据。
- `分工.md`：A → B → C 顺序接力安排。

当前是 A 阶段提交，`report/report.md` 为阶段报告，与 `A_report.md` 内容一致，供 C 后续合并扩充。已归档两张真实目标环境截图；完整 Lab3 原始评分待 B/C 完成后运行。B/C 的 `lab3 YOUR CODE` 标记保留供继续实现，A 阶段不删除或填空实现来绕过它们。

## 当前验证结论

静态核对通过：原始文件只变更两个内存文件，原始 Best-Fit 测试、同步代码、正式入口、Makefile、Trap 模块与评分工具保持原样。

Best-Fit 的原始两个自检在 Windows 宿主适配层中通过，最终空闲页计数恢复。它不是 QEMU 运行，也不验证 RISC-V 的中断/原子指令。

目标环境的编译、启动和阶段自检已通过，两张截图存放于 `report/images/`；下方命令供接力成员复现。WSL 原始文本日志暂未归档到交付目录。B/C 完成后再由 C 执行完整 `make grade`。

首次目标验证到达链接阶段，因原监视器依赖 `print_trapframe` 而失败。修正临时测试依赖边界后重试成功；正式监视器、Trap 和评分文件均未改。

## 在 Ubuntu 验证 A 阶段

如果还在 Windows PowerShell，先输入：

```powershell
wsl -d Ubuntu-24.04
```

以下命令全部在 Ubuntu 终端执行。代码复制到独立的 `lab3-a` 目录，保留此前 Lab1/Lab2：

```bash
mkdir -p ~/os-labs/lab3-a
cp -r "/mnt/c/Users/Lenovo/Documents/Codex/2026-09-29/lab1-http-8-135-34-58/outputs/lab3-deliverable/code" ~/os-labs/lab3-a/
cd ~/os-labs/lab3-a/code
bash tools/validate_a.sh env
```

环境输出确认 QEMU 为 4.1.1 后，截图命名为 `lab3_a_env.png`。如果提示 QEMU 路径不存在，指定实际的源码构建版本，例如：

```bash
export QEMU="$HOME/src/qemu-4.1.1-build/riscv64-softmmu/qemu-system-riscv64"
bash tools/validate_a.sh env
```

接着执行：

```bash
bash tools/validate_a.sh check
```

只有运行后出现以下标志才代表阶段验证成功；这里是预期标志，不是已经取得的目标运行结果：

```text
memory management: best_fit_pmm_manager
check_alloc_page() succeeded!
[A stage] allocation/accounting and disabled SIE preserved: PASS
[A stage] PASS; Trap and timer tests remain for B/C
```

正常会自动关机、回到 shell。截图命名为 `lab3_a_check.png`，保留命令、PASS 和回到 shell 的部分。超时退出或 `panic` 不视为成功。

日志自动保存在 `~/os-labs/lab3-a/report/logs/`。把日志复制回交接包：

```bash
cp -r ~/os-labs/lab3-a/report/logs "/mnt/c/Users/Lenovo/Documents/Codex/2026-09-29/lab1-http-8-135-34-58/outputs/lab3-deliverable/report/"
```

两张截图可以先保存在 Windows 截图目录，再放入交接包的 `report/images/`。验证后更新 A 章节中的待运行状态；如果失败，保留完整日志，先定位，不填写通过。

## 给 B 的继续开发要求

从本包完整目录继续修改 `code/kern/trap/trapentry.S` 的模块一标记，不用旧文件覆盖内存模块；`SAVE_ALL` 与 `struct trapframe` 保持不变，`YOUR CODE` 换成 B 的学号。

本阶段测试工具只用于验证 A，不要把临时入口覆盖进正式目录。正式 `make`/`make grade` 仍需等 B/C 的必做实现补齐。

B 交 C 时提供累计完整代码、本人章节和提示词，说明阶段验证范围。C 最终合并 `report.md`、补齐全部真实测试证据后交组长审核提交。
