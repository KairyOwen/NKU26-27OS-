# Lab4 A → B 交接说明

A：张哲宇（2412101）；B：刘梓涵（2410683）；C：李熔吉（2411310）。

## 已完成与已验证

A 已完成物理初始化与分配器恢复、Trap 恢复和分发、页插入和删除。原包 default_pmm.c 的缺失头文件已修正，保留 default_pmm_manager 接口，算法是 Best-Fit，以匹配原测试。

2026-11-17 已直接运行 QEMU 4.1.1：原 PMM/页表/别名内存访问/kmalloc/VMA 自检通过；同页映射权限更新、幂等删除、资源计数、第 1/2 次中间表分配失败回滚、普通与压缩断点返回均 PASS。日志见 report/logs。

正式 init.c、proc.c、sched.c、switch.S、Makefile、原评分与测试保持基线原样；完整 Lab4 尚未完成，不可将 A 阶段标志当成原始 30 分评分。

## B 从哪里继续

使用完整 code 目录，在 kern/process/proc.c 的 LAB4 function2 中完成 alloc_proc、proc_init、kernel_thread、do_fork、copy_thread、copy_mm，标记学号 2410683。不要把 proc.c 替换成历史版本，保留 function3 给 C。

Trap forkrets 已保留，RESTORE_ALL 按当前帧恢复，sp 最后加载。新线程首次现场由 B 组织，C 随后完成 proc_run/switch_to 实际运行。A 的恢复代码经过断点实测，但没有伪造新线程切换结果。

get_pte 新增 new_middle 回滚仅释放当前调用刚创建的中间页表；已存在页表不回收。page_remove 不主动释放空的上级页表，遵循当前框架生命周期，测试在结束时显式回收测试用表。

## Ubuntu 复现与截图

当前 Windows 完整目录：C:/Users/Lenovo/Documents/Codex/lab4-planning/deliverable。

在 Ubuntu 输入：

```bash
cd /mnt/c/Users/Lenovo/Documents/Codex/lab4-planning/deliverable/code
bash tools/validate_a.sh env
bash tools/validate_a.sh check
```

用户已完成复现，两张真实截图已保存为 report/images/lab4_a_env.png、lab4_a_check.png，并已在报告引用。日志自动写入 report/logs，不必另行复制。以上命令供 B/C 后续复现。

脚本在 /tmp 新建临时副本，临时入口位于 tools/a_stage_init.c；只构建内存和 Trap 相关目录，不链接未完成的进程与调度。正式入口不会被修改，成功时 SBI 关机，超时或 panic 不算通过。

## 交给 C 的材料

B 完成后将累计完整代码、本人章节、spec/prompt、修改清单和真实验证记录一起交 C。C 合并 report/report.md 与 prompt.md，运行完整 make grade 并补齐测试截图，最后 A 审核提交 lab4。

当前编译保留原 kmalloc.c 一处类型转换警告，不影响 A 运行。原 do_exit 的 panic 占位由本次教学框架提供，不能声称已经实现完整进程退出。
