# NKU26-27OS-

南开大学《操作系统》实验仓库（riscv64-ucore）。

小组成员：张哲宇（2412101，组长）、刘梓涵（2410683）、李熔吉（2411310）。

## 当前进度

更新日期：2026-11-17。当前推进 **Lab4：进程管理**，A 阶段已完成并上传，接下来由 B、C 顺序接力。

| 实验分支 | 实验内容 | 已确认进度 | 报告 |
|---|---|---|---|
| [lab1](https://github.com/KairyOwen/NKU26-27OS-/tree/lab1) | 最小可执行内核 | 已完成并提交，最终使用源码编译的 QEMU 4.1.1 验证 | [查看报告](https://github.com/KairyOwen/NKU26-27OS-/blob/lab1/report/report.md) |
| [lab2](https://github.com/KairyOwen/NKU26-27OS-/tree/lab2) | 物理内存和页表 | 已完成并提交，原评分 20/20，Buddy 测试和页表/TLB 调试已记录 | [查看报告](https://github.com/KairyOwen/NKU26-27OS-/blob/lab2/report/report.md) |
| [lab3](https://github.com/KairyOwen/NKU26-27OS-/tree/lab3) | 中断与异常处理 | 已确认 A 阶段提交；B/C 后续集成与完整评分状态待确认 | [查看报告](https://github.com/KairyOwen/NKU26-27OS-/blob/lab3/report/report.md) |
| [lab4](https://github.com/KairyOwen/NKU26-27OS-/tree/lab4) | 进程管理 | **A 阶段已完成并验证，B/C 待接力；完整实验评分尚未运行** | [查看阶段报告](https://github.com/KairyOwen/NKU26-27OS-/blob/lab4/report/report.md) |

## Lab4 接力安排

| 顺序 | 成员 | 工作 | 状态 |
|---|---|---|---|
| A | 张哲宇 | Lab2/3 基础适配，page_insert/page_remove，页表失败回滚与阶段验证 | 已完成，代码、报告、提示词、截图、日志已上传 |
| B | 刘梓涵 | PCB、idle/init、内核线程创建、首次运行现场与失败清理 | 接续 A 版本开发 |
| C | 李熔吉 | 调度、页表和上下文切换、最终集成与完整评分、报告合并 | B 完成后接力 |
| 最终审核 | 张哲宇 | 核对完整交付材料并提交最终版本 | C 完成后执行 |

A 阶段已在源码编译的 **QEMU 4.1.1** 中运行通过：物理分配器、页表、内核页别名读写、kmalloc/VMA 自检；同页重映射、权限更新、幂等删除与计数恢复；两次中间页表分配失败回滚；普通和压缩断点返回。

以上为阶段验证，不等于线程创建和调度已完成，也不等于已取得完整 Lab4 评分。

Lab4 入口：[代码](https://github.com/KairyOwen/NKU26-27OS-/tree/lab4/code) · [报告](https://github.com/KairyOwen/NKU26-27OS-/blob/lab4/report/report.md) · [提示词](https://github.com/KairyOwen/NKU26-27OS-/blob/lab4/report/prompt.md) · [截图](https://github.com/KairyOwen/NKU26-27OS-/tree/lab4/report/images) · [日志](https://github.com/KairyOwen/NKU26-27OS-/tree/lab4/report/logs) · [三人分工](https://github.com/KairyOwen/NKU26-27OS-/blob/lab4/report/分工.md) · [A → B 交接说明](https://github.com/KairyOwen/NKU26-27OS-/blob/lab4/report/A_交接说明.md)。

## 提交规范

每次实验使用一个 `labx` 分支，根目录包含 `code/` 和 `report/`。报告目录提供 `report.md`、`prompt.md` 和 `images/`，可另外保存真实运行日志。

成员开始接力前先拉取对应实验分支的最新提交，完成本人阶段后提交并推送，再交接下一人。

`main` 首页用于同步进度与提供入口。当前 main 中保留的 code/report 是此前合入的 Lab3 阶段材料；查看或继续 Lab4 请切换到 **lab4 分支**。
