# 操作系统实验报告

## 实验基本信息

| 项目 | 内容 |
|------|------|
| **实验名称** | Lab 2：物理内存和页表 |
| **小组成员** | 2412101-张哲宇、2410683-刘梓涵、2411310-李镕吉 |
| **完成日期** | 2026-10-22 |

### 小组分工

练习分工：

| 成员 | 负责的练习/模块 |
|------|----------------|
| 2412101-张哲宇 | page_init、环境与统一接入、最终测试和提交；协助准备 QEMU 调试环境 |
| 2410683-刘梓涵 | Buddy 实现与测试；Sv39 和 QEMU 源码 GDB 分支任务 |
| 2411310-李镕吉 | First-Fit 分析、Best-Fit 实现与分析；协助 Buddy 测试复核、提示词汇总 |

报告分工：

| 成员 | 报告内容 |
|------|----------|
| 张哲宇 | 环境、物理内存初始化、最终测试与整合 |
| 刘梓涵 | Buddy、页表与 TLB 调试、对应测试解释 |
| 李镕吉 | First-Fit/Best-Fit 分析、提示词和格式核对 |

本报告依据小组本轮实际代码、终端记录与截图编写。QEMU 4.1.1 下 Best-Fit 启动、课程评分 20/20、Buddy 行为测试，以及宿主/客体双 GDB 的页表查询、地址转换、软件 TLB 填充与命中查找均已有实际运行结果。算法辅助检查与客体实测分别记录，不用课程评分代替其他任务证据。

---

## 一、实验目的

1. 从设备树提供的硬件内存信息建立物理页描述符与初始空闲区。
2. 区分虚拟地址、物理地址、物理页号与 Page 指针，理解分页开启后的内存管理。
3. 理解 First-Fit，实现 Best-Fit 和 Buddy，比较连续页分配、碎片与合并策略。
4. 为无现成框架的 Buddy 设计可复现测试，用外部行为和状态不变量验证实现。
5. 使用宿主与客体两层 GDB 理解 QEMU 中的 Sv39 地址翻译及 TLB 行为。
6. 通过明确约束的提示词辅助实现，保留真实迭代与验证证据。

---

## 二、实验环境

| 项目 | 实际环境 |
|------|----------|
| 宿主与 Linux | Windows、WSL 2、Ubuntu 24.04 系列；内核 6.18.33.2-microsoft-standard-WSL2 |
| 目标 | RISC-V 64 位、QEMU virt、默认 128 MB RAM |
| QEMU | 4.1.1，源码编译；/home/lenovo/opt/qemu-4.1.1/bin/qemu-system-riscv64 |
| 交叉编译器 | riscv64-unknown-elf-gcc 13.2.0 |
| 客体调试器 | gdb-multiarch 15.1 |
| Make / Python | GNU Make 4.3 / Python 3.12.3 |
| 固件 | OpenSBI v0.4，Runtime SBI Version 0.1 |
| 实验目录 | ~/os-labs/lab2/code |
| 评分依赖 | bc 位于 /usr/bin/bc |

AI 工具：

| 成员 | AI 编程工具 | 底层模型 | 备注 |
|------|------------|---------|------|
| 张哲宇 | Codex 桌面应用 | 未记录具体型号 | 本轮统一辅助实现、检查与操作指导 |
| 刘梓涵 | 组长 Codex 会话（实现阶段）；DeepSeek Harness（交付复核/复现阶段） | 未记录 / DeepSeek-V4.1-Flash | 复核阶段仅用于 GDB 脚本迁移与证据核对，未生成内核实现代码 |
| 李镕吉 | 本轮由组长的 Codex 会话统一辅助 | 未单独记录 | 姓名表示分工责任，不表示另有个人 AI 会话 |

AI 工具名称与底层模型版本分别记录，不能只凭工具名推断模型。本轮另外在 Windows MSVC x64 原生适配环境验证分配器算法；该结果与 RISC-V 实测分开记录。第二环境复现由 2410683 在其 WSL 环境执行。

---

## 三、实验整体逻辑分析

### 2.1 本章节的逻辑主线

本实验解决“哪些物理页面可以分配、怎样组织和回收”的问题。每个 Page 描述一页物理内存，空闲块由管理器组织，内核通过统一接口分配和释放。Page 数组是管理元数据，其本身也占用物理内存，不能被分配器再次交出。

### 2.2 功能的逐步实现

1. entry.S 保存启动参数、建立启动页表并开启 Sv39，随后进入 kern_init；DTB 解析提供 RAM 范围。因此 page_init 执行时已经处于分页模式。
2. pmm_init -> init_pmm_manager 选择管理器并初始化内部状态。默认选择 Best-Fit，编译参数 PMM=buddy 可独立选择 Buddy。
3. page_init 校验内存范围、设置地址偏移和描述符布局，保留固件/内核/元数据，将剩余完整页面通过 init_memmap 注册。
4. alloc_pages/free_pages 通过管理器回调分配、拆分、回收和合并；nr_free_pages 反映空闲物理页数。
5. 运行框架检查、课程评分及 Buddy 自设计测试；GDB 分支进一步从模拟器实现观察地址翻译。

构建与评分配置：Makefile 相对原始代码包仅新增 PMM 选择开关（`PMM ?= best_fit`，`PMM=buddy` 时追加 `-DPMM_USE_BUDDY`）与 gdb 目标的 `$(GDB)` 变量替换；tools/grade.sh、tools/test_lab2.c、tools/test_lab2.h 等课程评分/测试文件与原始包逐字节一致，未修改评分逻辑。

---

## 四、实验内容与实现

### 功能模块一：物理内存初始化

**负责人：** 2412101-张哲宇。

#### 模块功能描述

```c
static void page_init(void);
```

实现位于 kern/mm/pmm.c，保留 lab2 function1 标记并填写学号。读取设备树 base/size，拒绝零长度、溢出和不受当前固定启动映射支持的基址；将管理终点限制在 PHYSICAL_MEMORY_END 后向下按页取整。固定映射和 nbase 基于 DRAM_BASE，本实现不声称支持任意硬件内存布局。

设置 va_pa_offset=PHYSICAL_MEMORY_OFFSET；npage 是管理上界的物理页号，描述符数量为 npage-nbase。pages 在链接符号 end 后按 4 KiB 对齐，先检查整个描述符数组能放入可管理内存，再将所有描述符置为保留、引用计数为零。

空闲起点等于描述符数组物理结束位置向上按页取整。只有起点小于管理终点时才调用 init_memmap，因此 OpenSBI、内核镜像、元数据及不完整页面均不进入空闲区。

本次 Best-Fit 实测与布局推导：

| 项目 | 数值与依据 |
|------|------------|
| DTB RAM 范围 | [0x80000000, 0x88000000)，128 MB，实测 |
| nbase / npage | 0x80000 / 0x88000，按页号推导 |
| 描述符数 | 32768，npage-nbase |
| 内核 end | VA 0xffffffffc0206078，实测 |
| 描述符起点 | PA 0x80207000，按页对齐推导 |
| 描述符大小 | RV64 ABI 下 struct Page 为 40 字节，数组共 0x140000 字节 |
| 空闲起点 | PA 0x80347000，运行输出与推导一致 |
| 初始空闲页数 | 31929，由终点与空闲起点的差除以 4096 推导 |

#### 最终提示词

完整记录见 prompt.md 的 P1，本模块最终任务规格为：

```text
阅读 pmm.c/pmm.h、memlayout.h、dtb.c、entry.S 和课程测试，实现 page_init。
保留 lab2 标记并填写 2412101；读取 DTB base/size，检查无效范围和溢出，
按固定映射设置 va_pa_offset，正确区分 npage 与 npage-nbase。
裁剪管理上界、向下按页对齐终点；在 end 后按页对齐放置 Page 数组并检查容量。
描述符先全部保留，排除固件、内核和描述符占用，向上对齐空闲起点。
仅在存在完整空闲页时调用 init_memmap；无效设备树必须 panic。
禁止修改测试，不把 page_init 描述为首次开启 Sv39。
```

#### 实现迭代过程

**第 1 次迭代**：按 P1 实现 page_init——读取 DTB 的 base/size，校验零长度、溢出和固定启动映射范围，按页设置 va_pa_offset、npage 与描述符数组，排除固件/内核/元数据后注册空闲区。

**问题与修订**：初版验证脚本在嵌套管道中运行 QEMU，未捕获固件输出，无法判定启动结果（见 prompt.md 实际迭代记录第 4 条）；这是验证流程问题，不是内核失败。处理：直接启动同一镜像确认成功，并修订脚本为直接调用 QEMU、stdin=/dev/null、显式 30 秒超时、去掉外层函数管道。结果：课程 page init 检查为 OK。

**关键改进点总结**：DTB 范围（零长度/溢出/映射支持）校验；npage 上界与描述符数组容量检查；OpenSBI、内核镜像、描述符等保留区排除；空闲起点按页向上对齐，只在存在完整页面时注册。脚本修订与复核详情见测试章节。

### 练习：硬件可用物理内存范围获取方法（Challenge 思考题）

**负责人：** 2412101-张哲宇。

OS 可以从启动固件或引导程序提供的硬件描述获取内存布局：本实验采用 RISC-V DTB 的 memory 节点，其他平台可能采用 UEFI 内存映射或 BIOS E820。需要同时识别保留区域、MMIO 与固件占用，并在启用分配前验证范围、溢出和对齐。设备树描述的是硬件内存资源，仍需扣除内核自身占用；盲目读写未知地址可能触发异常或设备副作用，不能作为通用发现方法。本节是分析回答，未声称新增硬件探测实现或已获得加分。

### 功能模块二任务一：理解 First-Fit

**负责人：** 2411310-李镕吉。

本节是阅读分析任务，不生成代码；First-Fit 分析作为 prompt.md 中 P2（Best-Fit 实现规格）的参考背景，未单列 prompt。分析验收标准是能解释初始化、按地址组织、首次匹配、拆分、回收合并与改进空间。

```c
static void default_init(void);
static void default_init_memmap(struct Page *base, size_t n);
static struct Page *default_alloc_pages(size_t n);
static void default_free_pages(struct Page *base, size_t n);
```

default_init 初始化空闲链表头并清零 nr_free。default_init_memmap 清除新注册页面的保留状态，重置引用计数，在首描述符记录块长度，按地址放入链表，并增加空闲页总量。

default_alloc_pages 从链表头查找第一个长度不小于请求的块。整块满足时删除节点；块较大时分出请求前缀，把剩余尾块放回原位置。清除已分配首块的 PageProperty，扣除实际交出的页数。

default_free_pages 重置回收页面状态，按地址插入空闲链表。先检查前块末端是否等于当前块起点，再检查后块是否紧接合并后的末端；符合条件才合并，撤掉不再作为首块的节点和标记。地址有序使“相邻链表节点”成为检查候选，但必须进一步验证物理连续。

**改进空间：**线性遍历可用分桶或索引减少搜索，但需权衡维护成本；可增加 Next-Fit 搜索游标或针对常见大小建立快速路径。回收时及时合并减少外部碎片，但连续分配仍会受到外部碎片影响，不能保证总空闲足够就一定成功。

### 功能模块二任务二：实现 Best-Fit

**负责人：** 2411310-李镕吉。

#### 模块功能描述

```c
static void best_fit_init(void);
static void best_fit_init_memmap(struct Page *base, size_t n);
static struct Page *best_fit_alloc_pages(size_t n);
static void best_fit_free_pages(struct Page *base, size_t n);
static size_t best_fit_nr_free_pages(void);
```

补齐 best_fit_pmm_manager 与全部回调，内部 free_area 的 free_list/nr_free 与框架测试约定一致，链表按地址组织；分配扫描满足请求的所有候选，选择最小块，同大小保留较低地址候选，遇到精确匹配可提前结束。拆分后只保留尾块空闲标记，释放后通过 insert_free_block 检查前后合并，分配与释放分别扣减、增加请求页数。

basic_check() 和 best_fit_check() 完整保留，已与压缩包正文比较确认未修改。pmm.c 默认选中 best_fit_pmm_manager，避免“写好模块却仍运行 First-Fit”的错误。

**改进空间：**当前查找为 O(k)，k 为空闲块数；可增加按块大小索引的平衡树、大小桶等，同时保留地址索引用于合并。Best-Fit 降低本次分配余量，不保证所有负载下外部碎片最少，也可能产生很多小块；需要结合工作负载评估。

#### 最终提示词

完整记录见 prompt.md 的 P2，本模块最终任务规格为：

```text
参考 First-Fit 与 pmm_manager，补齐 best_fit_pmm.c 全部管理函数和注册结构。
保留 basic_check/best_fit_check 原文，状态应兼容 free_list/nr_free 约定。
空闲块按地址组织，扫描选择最小可容纳块，同大小优先低地址，精确匹配可退出。
维护精确分配、尾块拆分、按地址回收和前后合并，以及 flags/property/ref/计数。
保留 lab2 标记并填写 2411310，默认管理器选 Best-Fit；回答改进空间。
```

#### 实现迭代过程

**第 1 次迭代**：按 P2 实现 best_fit 的全部管理回调与 best_fit_pmm_manager，直接实现分配扫描、拆分、按地址回收和前后合并。

**问题与修订**：课程骨架 best_fit_pmm.c 中 basic_check/best_fit_check 引用了 free_list/nr_free，但骨架本身未定义这些内部状态（free_area 是实现者自定义的容器），首版直接编译报未定义；与原始包正文比对确认是骨架预留后，按框架约定补 `static free_area_t` 与 free_list/nr_free 宏（不改两个测试函数），随后编译通过。

**第 2 次迭代**：接入默认管理器（pmm.c 默认选 best_fit_pmm_manager）并验证：Windows 原生适配保留 basic_check/best_fit_check 并跑 10000 次混合操作通过；QEMU 4.1.1 启动输出 memory management: best_fit_pmm_manager 与 check_alloc_page() succeeded!；make grade 得到两个 OK、Total Score 20/20。

**关键改进点总结**：按地址组织空闲链表以支持合并；扫描选择最小可容纳块、同大小优先低地址；精确匹配不拆分、较大块只保留尾块；释放时按地址插入并检查前后合并；分配/释放精确维护 nr_free 与页状态。

### 功能模块二任务三：Buddy System

**负责人：** 2410683-刘梓涵。

#### 模块功能描述

新增 buddy_pmm.c/.h 与 buddy_check.c。每阶维护空闲链表，块大小为 2 的幂页，按物理页号对齐，伙伴页号由 PPN XOR 块页数求得。初始非对齐区间拆成多个合法块；分配从足够大的阶开始寻找，逐级拆分；释放时只与同阶且空闲的正确伙伴合并。

```c
static void buddy_init(void);
static void buddy_init_memmap(struct Page *base, size_t n);
static struct Page *buddy_alloc_pages(size_t n);
static void buddy_free_pages(struct Page *base, size_t n);
static size_t buddy_nr_free_pages(void);
void buddy_check(void);
```

本框架管理上界对应 32768 页，因此最高阶为 15。非 2 的幂请求向上取整，如请求 3 页实际占用 4 页。分配首描述符记录原请求长度，专用 flags 位标记分配首块，ref 仍是引用计数。free_pages 必须传原请求页数且整块释放，不支持随意释放其中一部分。nr_free_pages 扣减和增加实际块大小，因此与 Best-Fit 的精确 n 页语义不同；接口允许分配不少于 n 页，报告明确这一约定。

通过 make PMM=buddy 独立启用，切换前 make clean。默认配置仍为 Best-Fit；不在活跃分配状态下直接替换管理器。

#### 最终提示词

实现与接入规格见 prompt.md 的 P3：

```text
从零实现 Buddy 并接入 pmm_manager，责任模块 2410683。使用每阶空闲链表，
按物理页号对齐，伙伴按 PPN XOR 块大小定位；支持不规则初始区间分解。
分配向上取 2 的幂并逐级拆分，释放仅合并合法同阶空闲伙伴。
最高阶对应当前固定上界；记录原请求但不占用 ref 的引用计数用途。
free_pages 使用原请求 n，回收完整取整块，检查分配首地址和请求长度。
统计实际占用页数，提供独立 PMM=buddy 配置，默认仍保持 Best-Fit。
```

针对生成实现的测试规格见 prompt.md 的 P4：

```text
另建测试源文件，通过接口检查具体 Buddy 实现，不能只复用内部公式。
覆盖非 2 的幂请求、逐级拆分、递归合并、相邻但非伙伴块、不规则初始区间、
耗尽及超上限请求、不重叠、不进入保留区、释放后统计恢复。
隔离区与真实物理页区分别测试，解释恢复初始状态的前提。
每类断言成功后才打印 PASS，说明这些行为能发现哪些错误及未覆盖的范围。
```

#### 实现迭代过程与测试有效性

**第 1 次迭代**：先实现管理器，再通过独立源文件检查外部行为：3 页请求导致空闲数减少 4，验证向上取整；释放后能重新分配 32 页，验证拆分后多级合并；只注册页号相邻但非伙伴的两页，断言 2 页分配失败，排除“任意相邻都合并”的错误。注册起始偏移 3、长度 61 的隔离区，逐页耗尽并检查地址唯一、边界和保留标记，交错释放后验证统计恢复与 32 页块可用；超出剩余总量或最大阶数的请求返回 NULL。隔离测试暂时替换描述符视图，完成后恢复真实视图并重建初始单一连续空闲区；本框架 page_init 只注册一个连续空闲区，这是该检查恢复过程的前提，不声称支持任意多个初始空闲区的原样快照恢复。

**问题与修订**：初版 Buddy 运行脚本在嵌套管道下同样未捕获固件输出，report/logs/buddy.log 只有 42 字节（`make: *** [Makefile:170: qemu] Terminated`），无法据此判定测试结果；处理为直接运行同一镜像/修订后的脚本，不把脚本问题当成内核失败。

**第 2 次迭代**：在真实空闲区验证不同大小分配、对齐、两两不重叠和全部释放后计数恢复；QEMU 4.1.1 实际输出四组 PASS、[Buddy] ALL TESTS PASSED、check_alloc_page() succeeded!，与原生适配结果一致。

**关键改进点总结**：分配首描述符记录原始请求长度、free_pages 必须传原请求 n 并整块回收；只与同阶且空闲的合法伙伴合并；非对齐、非 2 的幂初始区间分解为合法块；测试后恢复真实描述符视图与初始空闲区。测试尚未覆盖所有非法输入导致的 panic 分支或并发。

### 分支任务：GDB 调试页表查询过程

**负责人：** 2410683-刘梓涵；张哲宇协助环境。

#### 模块功能描述

本模块在宿主/客体两层调试器下动态观察一次内核取指如何从 Sv39 虚拟地址翻译为物理地址、如何被填入 QEMU 软件 TLB，并对照 QEMU 4.1.1 源码确认调用链。观测对象是 ucore lab2 内核镜像，不改内核和 Makefile；宿主 GDB 调试 QEMU 本体，客体 GDB 调试 RISC-V 内核，两端各用一个独立调试器会话。

本任务涉及的主要脚本（code/tools/gdb/ 共 10 个文件，完整清单见该目录 README.md）：

```text
code/tools/gdb/guest.gdb         单客体脚本：kern_entry 起单步打开 satp，观察 kern_init、PTE[511]、memset 参数
code/tools/gdb/guest-reset.gdb   复位流程客体侧：连接复位向量、等待宿主就绪后 detach
code/tools/gdb/guest-detach.gdb  detach 流程客体侧：先驱动内核到 kern_entry，再等待宿主交接
code/tools/gdb/host.gdb          宿主侧：QEMU 内部断点、命中条件与日志格式
code/tools/gdb/run-dual-reset.sh 首选双 GDB 流程：QEMU 从复位起跑，客体先连、宿主 attach 后客体 detach
code/tools/gdb/run-guest-gdb.sh  单客体运行：guest.gdb 驱动内核，QEMU -d mmu 生成 mmu.log
```

首轮环境中，已在独立 qemu-4.1.1-debug-build 目录使用 --enable-debug、--target-list=riscv64-softmmu、--disable-werror、--disable-docs 和 Python 3 配置并编译成功。configure 显示 CFLAGS=-g、TCG debug enabled yes；file 显示 x86-64、with debug_info、not stripped。保留原安装版，无需覆盖安装。宿主和客体分别使用一个 gdb-multiarch 实例；宿主根据 QEMU ELF 自动采用 x86-64，客体显式设置 riscv:rv64，不能把两个调试目标混淆。

静态源码已核对 QEMU v4.1.1：target/riscv/cpu_helper.c 包含 get_physical_address 和 riscv_cpu_tlb_fill；后者调用前者并在成功后调用 tlb_set_page。accel/tcg/cputlb.c 的 load_helper/store_helper 检查 TLB，未命中时可能尝试 victim TLB 或进入 tlb_fill，再调用架构回调；TCG 生成的快速访存路径也需结合源码说明，不能把 C 慢路径当成每次访存必经路径。

宿主 GDB 已实际附加到 QEMU 进程，设置条件断点 riscv_cpu_tlb_fill if (address >> 12) == 0xffffffffc0200。客体 GDB 继续运行后，宿主在取指填充路径命中，access_type=MMU_INST_FETCH、mmu_idx=1。随后通过临时断点进入 get_physical_address，实测 env->satp=0x8000000000080205、env->priv=1，确认 Sv39 与 S 模式。

在 cpu_helper.c:254、PTE 读取之后暂停，实测 levels=3、i=0、ptshift=18、base=0x80205000、idx=511、pte_addr=0x80205ff8、pte=0x200000cf。根页表项地址等于 base+511*8。PTE 的 V/R/W/X/A/D 置位，是根层叶子，对应 1 GiB 大页，因此本次查询不需要继续下降两层。

待翻译 VA 为 0xffffffffc02000d6。get_physical_address 返回码为 0，写出的 physical 是 0x80200000。这里函数输出为 4 KiB 物理页基址，不包含最低 12 位字节偏移；结合 VA&0xfff=0xd6，物理字节地址为 0x802000d6。另一种等价推导为大页物理基址 0x80000000 加 1 GiB 页内偏移 0x2000d6。不能把 physical=0x80200000 误判为翻译失败。

随后宿主在 tlb_set_page 实测 vaddr=18446744072637906944（0xffffffffc0200000）、paddr=2149580800（0x80200000）、prot=7、mmu_idx=1、size=4096。prot 是 QEMU 内部 PAGE_READ/WRITE/EXEC 权限位，不能直接当成 RISC-V PTE 编码。当前架构回调按 4 KiB 粒度交给软件 TLB，和页表本身使用 1 GiB 大页并不矛盾。这一步动态记录了填充入口参数，后续命中查找则进一步验证条目确已可用。

宿主继续运行后，客体在 kern_init 命中硬件断点，PC=0xffffffffc02000d6、satp=0x8000000000080205、&boot_page_table_sv39=0xffffffffc0205000。读取根表 VA+4088（第 511 项）得到 0x200000cf，与宿主读取结果一致。satp 的 PPN 左移 12 位得到 PA 0x80205000，和根表 VA 减 PHYSICAL_MEMORY_OFFSET 的结果一致。此处是两个调试器的动态交叉核对，不再仅依赖内核运行打印值。

最后在宿主给 get_page_addr_code 设置同页条件断点，在客体执行 si。宿主命中后逐行执行至 cputlb.c:1030，实测 addr=0xffffffffc02000d6、mmu_idx=1、index=0、entry->addr_code=0xffffffffc0200000；访问地址按 4 KiB 对齐后也为 0xffffffffc0200000。再次 next 直接来到第 1039 行，跳过 1031-1036 行的 victim TLB/填充处理，证明本次软件 TLB 查找命中。这是取指路径的一次动态观察，不外推为所有数据读写或所有访问都命中。

这条路径先按 MMU 索引与地址定位槽位，再用取指标签和访问页地址进行匹配；未命中时才尝试 victim TLB 或架构翻译回调。命中后还会检查 TLB_RECHECK/TLB_MMIO，普通 RAM 路径使用 addr+entry->addend 得到宿主访问指针，并转换为 QEMU RAM 地址。addend 和函数返回的 RAM 地址属于模拟器内部表示，不能当作客体物理地址；报告中的 VA->PA 数值来自前面的架构翻译函数。

Bare 模式在适用特权和访问条件下不进行 Sv39 多级页表翻译，但不能据此断言 QEMU 完全不使用软件 TLB：后者还服务于宿主内存访问、权限及 RAM/MMIO 路径。真实 CPU 的硬件 TLB 缓存地址翻译，而 QEMU 软件 TLB 在模拟器中还保存宿主访问所需的信息，二者不是同一个结构。M 模式和 MPRV 等条件也影响翻译路径，不能只看 satp 就概括所有访问。

#### 最终提示词

由 prompt.md 的 P6 提炼的自包含任务规格；报告正文只记录该规格的要点：

```text
输入：QEMU 4.1.1 源码与独立 --enable-debug 构建；code/ 下的 ucore lab2 镜像和
      code/obj/kernel 符号；宿主 GDB 与客体 RISC-V GDB 两个调试器实例。
目标：宿主调试器附加 QEMU 进程，依据真实源码定位 target/riscv/cpu_helper.c 的
      riscv_cpu_tlb_fill、get_physical_address 和 accel/tcg/cputlb.c 的
      tlb_set_page 与 TLB 查找路径；客体调试器经 gdbstub 连接 localhost:43210
      控制 ucore，逐步读出 satp、priv、根页表基址、idx、pte_addr、PTE、
      返回物理地址，并记录一次 tlb_set_page 的填充参数。
约束：用条件断点把观测限制在内核取指页；确认根层大页叶子，不强行假设三级查询；
      区分 helper 返回的物理页基址与加上页内偏移后的完整字节 PA；
      宿主暂停时客体 GDB 等待是正常现象；不改内核与 Makefile，不修改镜像。
判定：日志中能逐项找到 satp、pte_addr/PTE、physical、完整字节 PA 与
      tlb_set_page 参数；宿主与客体读数交叉一致；结论只引用实际观察，
      不把源码推导写成动态命中或回填完成的证据，每个关键节点明确截图时机。
```

#### 实现迭代过程

调试不是一次命中，按“问题→处理→结果”记录如下；各项均能对应 code/tools/gdb/ 下的脚本与 README，或 report/logs/ 中的日志（首轮日志在 report/logs/gdb-host.log，第二环境日志在 report/logs/gdb-b/）。

1. **QEMU 版本选择**：本机 PATH 默认的 `/opt/qemu/bin/qemu-system-riscv64` 是 7.0.0，其固件与符号均与 4.1.1 不同，不能用于本实验的启动与调试观测；用同一镜像实测该 QEMU 跑 make grade 为 0/20（两项 WRONG，见 report/logs/repro-b/grade-with-default-qemu-7.0.0.log）。处理：源码编译 QEMU 4.1.1（串口显示 OpenSBI v0.4、Runtime SBI 0.1），加 --enable-debug 保留调试符号，装在独立目录，不覆盖原安装版；脚本显式使用该 4.1.1。结果：make grade 为 20/20（report/logs/repro-b/grade-20-of-20.log），宿主 GDB 能显示 QEMU 源码行号并命中 TLB 路径断点（版本记录见 report/logs/gdb-b/environment.log 与 code/tools/gdb/README.md）。
2. **端口占用**：QEMU gdbstub 默认端口 1234 被 Windows 端微信（Weixin.exe）占用，QEMU 无法监听。处理：全部脚本统一改用 43210（`-gdb tcp::43210`），客体脚本用 `target remote localhost:43210` 连接，脚本注释与 README 写明原因。结果：双 GDB 均可正常连接。
3. **宿主附加权限**：WSL 2 每次实例重启都会把 kernel.yama.ptrace_scope 重置为 1；host GDB 用 `-p` 附加 QEMU 时被 Yama ptrace 策略拒绝（报错 `Could not attach to process ... ptrace_scope`），失败运行的日志已被随后的成功运行覆盖、未单独归档。处理：在同一个 WSL 会话内执行 `sudo sysctl -w kernel.yama.ptrace_scope=0` 后再运行。结果：`gdb <qemu-elf> -p <qemu-pid>` 成功进入 QEMU 进程（记录见 code/tools/gdb/README.md；gdb-b/environment.log 实测当时该值为 1）。
4. **客体 GDB 可用性**：以 root 用非登录 shell 切换用户运行时，PATH 不含 ~/riscv/bin，脚本找不到 riscv64-unknown-elf-gdb。处理：改用登录 shell（工具链位于 ~/riscv/bin 且已写入 PATH）重跑。结果：客体 GDB 正常连接 gdbstub（README 记录；该失败日志未归档）。
5. **长条件断点被截断**：首次把地址区间条件写成一行长命令，被终端换行截断，GDB 报语法错误（report/logs/gdb-host.log 第 1-2 行）。处理：改为 `(address >> 12) == 0xffffffffc0200` 的页号比较。结果：条件断点生效并在 riscv_cpu_tlb_fill 命中（report/logs/gdb-host.log 第 11 行条件生效、第 27 行命中）。
6. **重复同址断点**：同一位置被重复设置，出现 Breakpoint 1/2 并存（report/logs/gdb-host.log 第 17-23 行）。处理：`delete 2` 删除重复项后只保留一个断点。结果：命中记录唯一，便于读取变量。
7. **系统库源码缺失**：宿主停在 ppoll 时提示 `ppoll.c: No such file or directory`（report/logs/gdb-host.log 第 88 行）。处理：确认裸露的系统库调试信息缺失只影响系统库源码显示。结果：QEMU 源码断点、变量读取和调用链均不受影响。
8. **helper 输出粒度预期错误**：指导过程中曾预期 get_physical_address 直接给出完整字节 PA。处理：实测返回的是 4 KiB 物理页基址 0x80200000（report/logs/gdb-host.log 第 62-67 行），需再加 VA 低 12 位偏移 0xd6 得到 0x802000d6。结果：对“页基址/字节地址”的表述据实纠正，未把 physical=0x80200000 误判为翻译失败。
9. **Bare 模式断点**：分页未开启时 CPU 处于 Bare，kern_entry 只能用物理地址 0x80200000 下断；satp 尚未写入时也不能用虚拟地址断 kern_init，否则 QEMU 按 Bare 翻译虚拟地址会失败。处理：客体脚本先停在 kern_entry，单步到 satp 写入并执行 sfence.vma 之后再设置 kern_init 断点。结果：客体在 Sv39 已开启的状态下命中 kern_init。
10. **satp 开启后的反汇编**：写 satp 后 PC 寄存器里是物理地址，直接 `x/2i 0x80200038` 会报 `Cannot access memory`。处理：加直接映射偏移 0xffffffff40000000 换算为虚拟地址后再反汇编（见 guest.gdb 脚本注释）。结果：单步上下文正确对齐到 entry.S。
11. **双 GDB 时序**：若客体先停在 kern_entry、宿主再 continue，会把 vCPU 一起放行，客体 GDB 再 continue 会报 `Cannot execute this command while the target is running`；若宿主先附加，QEMU 停在复位、客体又无法就位。处理：固定为“客体连接并停住 CPU → 宿主 attach 安装断点 → 客体 detach 放行”的顺序，用 `/tmp/guest_ready`、`/tmp/host_ready` 两个标志文件同步（run-dual-detach.sh / run-dual-reset.sh）。结果：双 GDB 交替控制不再抢跑，宿主能看到从 OpenSBI 到 Bare 取指、再到首次 Sv39 页表查询的完整序列。
12. **SIGPIPE 干扰**：QEMU 向已关闭的终端写数据时，宿主 GDB 默认会停在 SIGPIPE 上，打乱继续/单步时序。处理：宿主脚本设置 `handle SIGPIPE nostop noprint pass`。结果：调试会话不再被该信号打断。
13. **日志可读性**：同一次运行中同一页可能被多次填充，重复打印会淹没有效记录。处理：脚本用一次性标志（如 `$bare_seen`、`$code_fill_logged`、`$data_fill_logged`）只记录首次命中，并把宿主、客体与串口输出分别写入日志文件。结果：每次运行的证据可按文件定位，见 report/logs/gdb-b/。

#### 与大模型协作解决的问题

本小节记录调试与交付复核过程中与 AI 助手协作解决的真实问题：首轮调试使用组长的 Codex 会话，交付复核阶段使用本地 AI 助手（DeepSeek Harness）。模型输出全部用实际日志核对后才写入报告。

**案例 1（交付复核）：GDB 脚本跨构建迁移**

- 情景：旧脚本按另一套构建硬编码了 `0xffffffffc0206ff8`（PTE[511] 的 VA）与 `0xffffffffc0207018/0xffffffffc0207000`（edata 数据页）；当前 lab2 构建实测 PTE[511] 在 `0xffffffffc0205ff8`、edata=`0xffffffffc0206018`，直接运行会观测不到目标地址。
- 思路：把当前构建布局（end/edata/boot_page_table_sv39/free begin 与串口输出）、旧脚本清单和期望日志字段一起交给模型，要求只改地址、日志目录与端口，不改变断点条件与调试逻辑，并说明每处改动的依据。
- 交互过程：模型按布局给出地址替换表（含 PTE 的 +0xff8 偏移与数据页换算），并保留 run-dual-reset.sh 的同步标志逻辑；我们逐项对照 report/logs/gdb-b/guest-gdb.log、host-gdb.log 验证 satp、PTE、VA→PA 与 TLB 填充均命中后才定稿，README 的“脚本按当前构建改了什么”一节记录改动清单。
- 结论：迁移后的脚本在第二环境跑出与首轮一致的观测值，迁移正确；未改动内核与 Makefile。

**案例 2（交付复核）：双 GDB 无法 attach / 连接失败**

- 情景：复核阶段第一次运行脚本时，宿主 GDB attach 被 Yama 拒绝（报错提示 `Could not attach to process ... ptrace_scope`）；另一次以 root 用非登录 shell 运行时 PATH 不含 `~/riscv/bin`，脚本找不到 riscv64-unknown-elf-gdb。
- 思路：把两条报错原文与 WSL 2 环境（每次实例重启会重置 kernel.yama.ptrace_scope）交给模型，要求给出可验证的根因与最小修正，而不是反复重试。
- 交互过程：模型给出“在同一个 WSL 会话内 `sudo sysctl -w kernel.yama.ptrace_scope=0`”与“改用登录 shell/绝对路径”的修正；按其重跑后宿主成功 attach、客体正常连接，日志与 README 均记录成功路径。失败运行的日志已被成功运行覆盖、未单独归档，报告不把失败记录说成有日志留存。
- 结论：问题定位为权限与 PATH 配置，不是脚本逻辑错误；修正后双 GDB 稳定运行。

**案例 3（首轮调试）：helper 输出粒度与断点条件**

- 情景：曾预期 `get_physical_address` 直接输出完整字节 PA，实测只给 4 KiB 页基址 `0x80200000`；同时长地址区间条件断点被终端换行截断，GDB 报语法错误，断点未生效。
- 思路：把 GDB 输出（physical、VA&0xfff、报错原文）与 QEMU 源码行号交给模型，要求区分“页基址/字节地址”并给出可执行的断点条件改法。
- 交互过程：首轮把 GDB 输出（physical、VA&0xfff、报错原文）与 QEMU 源码位置交给 AI 助手核对，得到加页内偏移与页号比较的改法；复核阶段用 report/logs/gdb-host.log 第 62-67 行、第 11/27 行再次核对后才写入报告。
- 结论：两处修正均经日志验证；报告按实际观测表述，不把源码推导写成动态结果。

方法论：把版本、命令、日志与期望值作为输入，要求模型给出能在源码/日志中核对的位置与参数；不采纳未实测的结论，模型输出只作假设，最终以日志为准。

#### 双 GDB 复现（刘梓涵环境）

本节是把已交付的 code/tools/gdb/ 脚本在第二台 WSL 2 机器上重新运行得到的独立复现，不是另一套实现；用途是交叉核对首轮观测与当前 lab2 构建布局，数值以日志为准。

环境版本（report/logs/gdb-b/environment.log 实测）：

| 项目 | 实际值 |
|------|--------|
| 宿主 | Windows + WSL 2，Ubuntu 26.04 LTS，内核 6.18.33.2-microsoft-standard-WSL2，18 CPU / 15 GiB，用户 hanmiao33 |
| QEMU | 4.1.1 源码编译（--enable-debug），`$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64`；PATH 上的 `/opt/qemu/bin` 为 7.0.0，本实验不使用 |
| 交叉编译器 | riscv64-unknown-elf-gcc 16.1.0，binutils 2.47 |
| 宿主 GDB | /usr/bin/gdb 17.1 |
| 客体 GDB | riscv64-unknown-elf-gdb 17.2 |
| gdbstub 端口 | 43210（1234 被 Windows 微信占用） |
| ptrace | 环境日志实测 kernel.yama.ptrace_scope=1；WSL 重启会重置为 1，运行脚本前需在同一会话内设为 0 |
| Make / Python | GNU Make 4.4.1 / Python 3.14.4 |

复现命令与流程：

1. `cd code && make clean && make`：默认 best_fit 构建，与报告其余证据使用同一份代码（本次执行等价命令 `make -j4`；构建日志见 report/logs/repro-b/build-best-fit.log）。
2. `sh tools/gdb/run-dual-reset.sh`：脚本以 `-S` 启动 QEMU 并开 `-gdb tcp::43210`；客体 GDB 先连接复位向量（pc=0x1000）并停住、写 `/tmp/guest_ready` 等宿主；宿主 GDB 用 `gdb <qemu-elf> -p <qemu-pid>` attach，加载 tools/gdb/host.gdb 安装断点、写 `/tmp/host_ready`；客体 GDB detach 后 QEMU 从复位开始运行，宿主从 OpenSBI 依次观察到 Bare 首取指、Sv39 取指与 memset 数据 store。
3. `sh tools/gdb/run-guest-gdb.sh`：客体脚本 tools/gdb/guest.gdb 从 kern_entry 单步打开 satp，在 kern_init 读取 boot_page_table_sv39[511]，在 memset 入口记录参数；QEMU 同时以 `-d mmu` 生成 mmu.log。

实测数值（逐项来自 report/logs/gdb-b/；页表遍历与取指翻译与首轮一致，数据 store 的翻译与 TLB 填充为本环境新增观测）：

| 观测点 | 实测值 | 日志 |
|--------|--------|------|
| 客体 kern_entry | pc=0x80200000、satp=0（Bare） | guest-gdb.log 第 8-11 行 |
| 客体写 satp 后 | 15 次 stepi 后 satp=0x8000000000080205、pc=0x80200038 | guest-gdb.log 第 34-38 行 |
| 客体 kern_init | pc=0xffffffffc02000d6、satp=0x8000000000080205 | guest-gdb.log 第 44-47 行 |
| 客体 PTE[511] | VA 0xffffffffc0205ff8 → 0x200000cf，satp PPN=0x80205 | guest-gdb.log 第 48-50 行 |
| 客体 memset 入口 | a0(s)=0xffffffffc0206018、a1(c)=0、a2(n)=0x60 | guest-gdb.log 第 57-60 行 |
| 宿主 Bare 取指 | tlb_fill(0x80200000, MMU_INST_FETCH, mmu_idx=1) → Bare 分支 *physical=0x80200000 | host-gdb.log 第 17-23 行 |
| 宿主 Sv39 取指 | VA 0xffffffffc02000d6 → satp=0x8000000000080205、priv=1、i=0、idx=511、pte_addr=0x80205ff8、pte=0x200000cf、physical=0x80200000（字节 PA 0x802000d6） | host-gdb.log 第 25-36 行 |
| 宿主 TLB 填充（取指） | vaddr_page=0xffffffffc0200000、paddr=0x80200000、index=0；mmu_idx=1（tlb_fill 上下文，第 25 行） | host-gdb.log 第 25、35-36 行 |
| 宿主数据 store | VA 0xffffffffc0206018 → physical=0x80206000（字节 PA 0x80206018 = 页基址 0x80206000 + VA 低 12 位 0x18） | host-gdb.log 第 38-45 行 |
| 宿主 TLB 填充（数据） | vaddr_page=0xffffffffc0206000、paddr=0x80206000、index=6 | host-gdb.log 第 46-47 行 |
| mmu.log 交叉核对 | 取指 VA 0xffffffffc02000d6 与数据 VA 0xffffffffc0206018 均 ret 0，physical 分别为 0000000080200000、0000000080206000，prot 7 | mmu.log 第 89-90、95-96 行 |

tlb_set_page 的调用参数：vaddr_page=0xffffffffc0200000、paddr=0x80200000 在 cputlb.c:836（tlb_set_page_with_attrs 内 tn 填充处）实测；mmu_idx=1 由 tlb_fill 上下文实测；prot=7（PAGE_READ|PAGE_WRITE|PAGE_EXEC）由 cpu_helper.c 调用点与 mmu.log 中该页翻译返回的 prot 7 确定；size=TARGET_PAGE_SIZE=0x1000，是该版本 4 KiB 填充粒度。tn.addr_read/addr_write/addr_code 也一并写入 host-gdb.log 第 36 行。

构建布局与 A 环境的一致性：完整串口输出（serial-reset.log）实测 entry=0xffffffffc02000d6、etext=0xffffffffc02016be、edata=0xffffffffc0206018、end=0xffffffffc0206078、free begin=0x80347000、satp VA=0xffffffffc0205000 / PA=0x80205000。其中 edata、end、boot_page_table_sv39 与空闲起点与 A 环境（report/logs/best-fit.log）完全一致；唯一差异是 etext 0xffffffffc02016be 对 A 环境的 0xffffffffc02016b0，相差 0xe 即 14 字节，原因是交叉编译器版本不同（13.2.0 对 16.1.0）。该差异只影响 .text/.rodata 的长度，.data 段按 4 KiB 对齐后的地址不变（实测 edata、end 相同），因此上述关键地址和 GDB 观测值可直接对照。

与首轮环境的两处配置差异：gdbstub 端口由默认 1234 改为 43210（1234 被 Windows 微信占用）；宿主 GDB attach 前必须在同一个 WSL 会话内把 kernel.yama.ptrace_scope 置 0（WSL 重启会重置为 1）。

日志位置：report/logs/gdb-b/ 下，run-dual-reset.sh 产出 guest-reset.log、host-gdb.log、host-stdout.log、serial-reset.log、qemu-reset.log；run-guest-gdb.sh 产出 guest-gdb.log、mmu.log、serial.log、qemu.log；environment.log 为环境版本记录。serial.log 在客体 detach 后 QEMU 被脚本立即终止，末尾截断属真实行为，完整启动输出看 serial-reset.log。复现构建、Buddy 与 grade 的日志在 report/logs/repro-b/。本轮复现以完整日志作为证据，未新增截图；报告中 GDB 截图均来自首轮环境（report/images/），其数值与本节日志一致。

#### 观察软件模拟硬件的收获

1. **直映射偏移换算**：lab2 的内核符号是虚拟地址，QEMU 记录的是物理地址，两者相差直接映射偏移 `0xffffffff40000000`；若用物理地址值直接反汇编，会得到错误结果，需要先换算成虚拟地址。
2. **helper 返回页基址，不等于完整字节 PA**：`get_physical_address` 写出的是 4 KiB 页基址（本次为 `0x80200000`），完整字节地址还要加 `VA & 0xfff`（`0x802000d6`）；数据页同理（`0x80206018 = 0x80206000 + 0x18`）。判读日志时必须区分这两层。
3. **大页叶项与软件 TLB 粒度并存**：根页表 PTE[511] 是 1 GiB 大页叶项，但 QEMU 架构回调按 4 KiB 粒度调用 `tlb_set_page`，因此同一次翻译会同时出现“1 GiB 映射”和“4 KiB 填充”两种粒度，二者并不矛盾。
4. **QEMU 软件 TLB 不是真实 CPU TLB**：它还保存宿主访问指针、权限（prot=7）与 RAM/MMIO 判断所需的信息；真实 CPU 的硬件 TLB 只缓存地址翻译。观察模拟器时要把“客体地址翻译”与“模拟器内部访存缓存”分开。

### Challenge：SLUB

**负责人：** 全体成员（选做任务，未实现，不声称完成或加分）。

未实现，不声称完成或已获加分。其核心是在页级管理器上建立对象缓存和页内空闲对象管理，从而支持小于一页的不同大小对象；本实验的已实现部分仍为页级分配。

---

## 五、测试与验证

| 检查 | 实际状态 | 能证明的范围 |
|------|----------|--------------|
| 环境版本 | 已收到 Ubuntu 输出 | QEMU 4.1.1、GCC/GDB/Make/Python 和 bc 可用 |
| 干净编译与 Best-Fit 启动 | 已通过 | RISC-V 内核启动、DTB 初始化、默认 Best-Fit 框架检查 |
| make grade | 20/20 | 脚本中的 Page Init 与 Best-Fit 检查 |
| Buddy 独立镜像 | 四组 PASS，总检查通过 | 当前自设计测试覆盖的行为与边界 |
| Windows 原生算法检查 | 已通过 | 真实分配器源文件的算法行为，不包含硬件启动 |
| 修订后的 validate.sh | 已在 Ubuntu 复核通过 | 非交互启动、30 秒超时和默认 Best-Fit 恢复 |
| 双 GDB 分支 | 页表查询、地址转换、TLB 填充、客体交叉核对与取指 TLB 命中均已实测 | 页表层级、页基址/字节地址及缓存路径 |
| 独立复现（2410683 环境） | 另一台 WSL 2 机器重新构建后 Best-Fit 布局与报告一致（end=0xffffffffc0206078、free begin=0x80347000、satp PA=0x80205000）；Buddy 配置四组 PASS + check_alloc_page() succeeded；显式指定 QEMU 4.1.1 重跑 make grade 20/20（PATH 默认 7.0.0 同一镜像为 0/20）；双 GDB 日志见 report/logs/gdb-b/ | 日志见 report/logs/repro-b/ 与 report/logs/gdb-b/；同一交付在另一环境的构建与运行可复现，不替代首轮证据 |
| 截图归档 | 截图已归档并检查：4 张基础截图 + 6 张 GDB 截图，共 10 张；grade 截图为 tools/validate.sh grade（内部调用 make grade） | 环境、Best-Fit、课程评分、Buddy 与 GDB 观测 |

独立复现（2410683 环境）：在另一台 WSL 2 机器上重新构建同一份交付代码后，Best-Fit 启动输出的 entry/edata/end、free begin 与 satp VA/PA 与报告一致（etext 因编译器版本不同差 14 字节，原因见分支任务一节）；`make PMM=buddy` 的 Buddy 配置四组 PASS 且 check_alloc_page() succeeded；显式指定 QEMU 4.1.1 重跑 make grade 为 20/20，而同一镜像直接用 PATH 默认的 QEMU 7.0.0 跑 grade 为 0/20，说明必须显式指定 4.1.1。构建、启动、Buddy 与两份 grade 日志见 report/logs/repro-b/，双 GDB 日志见 report/logs/gdb-b/。这是同一交付在另一台机器上的重跑，不构成第二套实现，也不改变首轮结论。构建命令为 `make clean && make`（默认 Best-Fit）与 `make clean && make PMM=buddy`（Buddy 复现）；grade 对照显式指定 `QEMU=~/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64`（详见 code/tools/gdb/README.md）。

已收到的课程评分输出：

```text
  -check page init:                          OK
  -check best fit:                           OK
Total Score: 20/20
```

已收到的 Buddy 输出：

```text
[Buddy] rounding, split, recursive merge: PASS
[Buddy] adjacent non-buddies stay separate: PASS
[Buddy] irregular range, exhaustion, no overlap: PASS
[Buddy] real memory and accounting recovery: PASS
[Buddy] ALL TESTS PASSED
check_alloc_page() succeeded!
```

**测试截图：**

环境版本：

![QEMU 4.1.1 和工具链版本](./images/lab2_env_versions.png)

Best-Fit 编译后的直接启动结果：

![Best-Fit 初始化与框架检查](./images/lab2_make_qemu.png)

课程评分：

![Page Init 与 Best-Fit 评分 20/20](./images/lab2_grade.png)

Buddy 独立运行：

![Buddy 四组行为检查全部通过](./images/lab2_buddy_tests.png)

宿主进入 TLB 填充路径：

![QEMU 取指翻译入口及调用链](./images/lab2_gdb_host_tlb.png)

根层大页页表查询：

![根页表项读取及层级变量](./images/lab2_gdb_host_walk.png)

翻译结果：

![物理页基址和字节地址核对](./images/lab2_gdb_host_translation.png)

TLB 填充参数：

![软件 TLB 填充的页地址、权限与粒度](./images/lab2_gdb_host_tlb_fill.png)

客体侧交叉核对：

![客体 PC、satp 与根页表第 511 项](./images/lab2_gdb_guest_satp.png)

TLB 命中查找：

![取指标签匹配并跳过未命中分支](./images/lab2_gdb_host_lookup.png)

原生检查日志见 report/logs/host-algorithms.log。Ubuntu 环境、构建、直接启动、课程评分及宿主 GDB 日志已从操作者目录汇总到 report/logs/。其中 buddy.log 保留初版脚本无固件输出的失败记录，成功的 Buddy 运行应查看 buddy-direct.log；不将失败日志冒充成功结果。report/logs/ 为测试与调试证据附录，不属于课程模板要求的报告目录。

初版脚本在嵌套管道中运行 QEMU 时未捕获固件输出，直接启动同一镜像则成功。修订为直接调用 QEMU、stdin=/dev/null、30 秒超时并移除外层函数管道后，操作者再次干净构建并运行 Best-Fit，实际出现固件与内核输出、check_alloc_page 成功和默认管理器名称，脚本正常返回。现象支持修订有效，但未单独隔离每项改变的因果关系，不断言已严格证明底层根因。超时结束常驻内核本身不是失败，通过条件仍是实际检查标志且无 panic。

---

## 六、实验总结与收获

### 对操作系统的理解

1. 物理页描述符是 OS 的管理数据，物理页面是资源本身；描述符索引加 nbase 得到物理页号，不能把 Page 指针直接当作 PA。
2. 地址翻译和物理页分配是两件相互配合的工作：Sv39 负责访问地址如何映射，分配器负责哪些物理页空闲。page_init 不等于首次开启分页。
3. First-Fit/Best-Fit 面临外部碎片；Buddy 用对齐的幂次块简化拆分合并，但向上取整产生内部碎片。统计总空闲页不等于保证任何连续请求成功。
4. 固件保留、内核镜像和元数据占用体现了资源所有权约束；对齐、边界和不变量与核心算法同样重要。
5. 本实验未覆盖完整多进程地址空间、缺页异常和页面置换、用户态隔离、NUMA/并发分配、完整对象缓存等机制，不能把最小实现等同于生产级内存管理。

**知识点与 OS 原理对应关系：**

| 知识点 | 对应 OS 原理 | 含义、关系与差异 |
|--------|--------------|------------------|
| Page 描述符 | 物理内存管理 / 页框管理 | Page 数组描述每个物理页框的状态（保留、空闲、引用计数）；它是管理元数据，本身占用内存，不能当资源再分配 |
| First-Fit / Best-Fit | 连续内存分配与外部碎片 | 都按地址维护空闲块链表；First-Fit 取首个可容纳块，Best-Fit 取最小可容纳块；选择策略影响碎片形态，但不保证总空闲够就一定能满足连续请求 |
| Buddy System | 伙伴系统与内部碎片 | 空闲块按 2 的幂对齐，伙伴由页号 XOR 定位；拆分/合并快、外部碎片受控，但向上取整产生内部碎片；与 First-Fit/Best-Fit 的精确页数语义不同 |
| Sv39 / PTE / satp | 多级页表与地址翻译 | satp 给出页表基址与模式，PTE 逐级翻译虚拟地址；本实验的启动页表用 1 GiB 大页覆盖直接映射区 |
| TLB | 快表 / 地址翻译缓存 | 缓存近期翻译结果；真实 CPU 用硬件 TLB，QEMU 用软件 TLB 并附带宿主访问信息，两者结构与用途不同 |
| page_init / DTB / 保留区 | 启动内存探测与资源所有权 | 从固件设备树获取内存范围，扣除固件、内核镜像与元数据后登记空闲页；体现“哪些内存归谁使用”的所有权约束 |

### AI 协作开发的经验

提示词必须提供真实接口、保留区和测试约束，不能只要求“实现某算法”。无框架任务需要先固定分配/释放契约，再生成针对该契约的测试。原生算法测试、客体启动、课程评分与源码调试证明不同层面的性质，不能互相替代。遇到无输出时应先区分构建、启动脚本和内核，再定位问题；所有最终结论以真实运行和证据为准。
