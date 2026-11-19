# Lab4 A/B 阶段：实际需求与实现约束

## 实际用户需求

本次用户提供 Lab4 指导材料与 lab4.zip，先要求三人分工，随后要求“接下来完成A需要做的任务吧”。此前已经约定 A → B → C 接力、C 最终集成、A 审核提交。

## 本次实现 spec（归纳记录）

以下是本次依据代码审阅形成的实现约束，供复核与交接，不冒充用户曾逐字发送的提示词：

```text
以 lab4_new 为基线完成 A：
迁移当前包的 lab2/lab3 空缺，实现 page_insert/page_remove。
保留 kmalloc、VMA、forkrets、新页表工具和关中断包装；
不填 B/C 的 function2/function3，不改原测试和通过条件。
同页重映射净引用不变；异页替换正确减少旧引用；
删除无映射幂等，更新 PTE 后失效对应 TLB。
get_pte 分配失败返回 -E_NO_MEM；本次新增中间表须回滚，
不能破坏旧表或使目标物理页引用增加。
用真实 WSL/QEMU 4.1.1 隔离验证 A，不把阶段测试当成完整 grade。
```

## 实际核对与迭代

1. 查明 default_pmm.c 引用缺失的 best_fit_pmm.h，而原测试为 Best-Fit；改用现存 default_pmm.h，在 default_pmm_manager 接口内实现 Best-Fit，保留测试原文。
2. 根据当前 KERNBASE/KERNTOP 与偏移计算物理界限，按 DTB、Page 描述符和对齐条件恢复初始化。
3. 第一轮目标运行通过原 PMM、页表、kmalloc、VMA 自检，以及额外的同页重映射、权限和幂等删除检查。
4. 针对 get_pte 第二次页分配失败的残留问题补充最小回滚，增加允许分配 0/1 个页的故障注入；实测错误码、目标引用、上级项和空闲计数保持一致。
5. 增加 32 位与压缩断点返回检查，确认恢复实现实际可返回；保留 forkrets，完整线程首次运行仍由 B/C 验证。

## B 阶段：PCB 与线程创建初始化

### 实际用户需求

本次用户提供 Lab4 A 阶段交接包、lab4.zip 和课程材料，要求基于完整 `code` 目录继续实现 `kern/process/proc.c` 的 `LAB4 function2`，保留 A 的修改和给 C 的 `function3` 区域；完成后把累计代码、本人报告与提示词交给 C 集成。

### 本次实现 spec（归纳记录）

```text
输入：Lab4 A 阶段累计代码；A 已迁移 Lab2/3 内存与 Trap 基础；
      proc.c 只有 function2、function3 两个待实现区域。
任务：在 LAB4 function2 中实现 alloc_proc、proc_init、kernel_thread、
      do_fork、copy_thread、copy_mm，把标记换成 2410683。
要求：
1. alloc_proc 分配 PCB 并显式初始化 state、pid、runs、kstack、
   need_resched、parent、mm、context、tf、pgdir、flags、name。
2. proc_init 初始化进程链表与 PID 哈希，建立 idleproc（pid 0、
   RUNNABLE、kstack=bootstack、need_resched=1），再通过 kernel_thread
   创建 initproc（pid 1、RUNNABLE、parent=idle、mm=NULL）。
3. kernel_thread 把 fn/arg 放入 s0/s1，设置 SPP/SPIE 与 epc=
   kernel_thread_entry，调用 do_fork(CLONE_VM,...)。
4. do_fork 完成 PCB、内核栈、mm、现场、pid/hash/list/nr_process 登记，
   共享状态更新放入关中断临界区；失败逆序回收，不提前发布 runnable。
5. copy_thread 把 trapframe 放到新内核栈顶，子进程 a0=0，设置 sp 与
   context.ra=forkret、context.sp=tf。
6. copy_mm 只处理共享内核空间的内核线程，不实现用户进程 fork。
7. 不修改 A 的基础迁移、C 的 function3、原测试和评分条件。
判据：编译通过；隔离测试 [Test PMM] 与 [Test Process Create] PASS；
      调度和完整 make grade 待 C，不把临时桩结果当成满分。
```

### 实际核对与迭代

1. 按 `proc.h` 字段和测试断言固定 PCB 初值；把 `copy_mm`/`copy_thread` 放在 `do_fork` 之前，避免隐式声明。
2. `do_fork` 的 pid/hash/list/nr_process 更新统一放入 `local_intr_save` 临界区；失败路径按 PCB、内核栈逆序回收。
3. 在临时副本中为 C 的 `cpu_idle`/`proc_run`/`schedule` 放桩，注入测试后以 QEMU 4.1.1 运行，得到 `[Test PMM] PASS`、`[Test Process Create] PASS`。
4. 真实环境问题：GCC 16 将原包 kmalloc.c 的整数到指针转换视为 error，注入的 test_lab4.c 还有 void/int 函数指针不匹配；B 未改 A/测试源码，隔离验证使用临时编译参数 `-Wno-int-conversion -Wno-incompatible-pointer-types`，该问题需 C/A 统一处理。
5. 未运行调度测试、initproc 实际执行和原始 30 分评分；这些留给 C，不能把 B 的阶段 PASS 写成完整通过。

## 记录边界

以上为本次真实实现过程的归纳，不虚构历史提问或失败输出。测试先由 Codex 调用 WSL 执行，用户随后于 2026-11-17 复现并提供两张真实终端截图，已归档到 report/images。A 阶段未记录具体模型型号，未运行完整 Lab4 评分。B 已补充“B 阶段：PCB 与线程创建初始化”的实际 prompt 与问题处理；C 后续追加调度、切换与最终评分记录，不把分阶段结果写成完整通过。
