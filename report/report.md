# 操作系统实验报告

## 实验基本信息

| 项目 | 内容 |
|------|------|
| **实验名称** | Lab 1：比麻雀更小的麻雀（最小可执行内核） |
| **小组成员** | 【2412101-张哲宇】、【2410683-刘梓涵】、【请填写：学号-姓名】 |
| **完成日期** | 2026-10-8 |

### 小组分工

练习如何分工？

| 成员 | 负责的练习/模块 |
|------|----------------|
| A：【2412101-张哲宇】 | 环境搭建与验证、练习 1-1（Makefile 构建过程）、测试与验证、仓库与提交管理 |
| B：【2410683-刘梓涵】 | 练习 1-3、练习 2、GDB 调试体验、实验整体逻辑分析 |
| C：【学号-姓名】 | 练习 1-2（链接脚本）、SBI 到 stdio 调用链、实验目的与总结、全文格式终检 |

实验报告如何分工？

| 成员 | 负责的报告章节 |
|------|---------------|
| A：【2412101-张哲宇】 | 二、实验环境；四（练习 1-1）；五、测试与验证 |
| B：【2410683-刘梓涵】 | 三、实验整体逻辑分析；四（练习 1-3、练习 2、GDB 调试体验） |
| C：【学号-姓名】 | 一、实验目的；四（练习 1-2、SBI 到 stdio）；六、实验总结与收获；全文组装与格式终检 |

实验报告由三位成员分别完成负责章节，最后统一合并到 `report.md`。A 负责检查分支、目录和提交规范；C 负责全文格式终检及提示词、截图归档。

---

## 一、实验目的

> 本节由 C 负责，以下内容可作为合并基础。

1. 理解一个最小 RISC-V 内核从源文件到可执行镜像的完整构建过程。
2. 理解 ELF 内核与纯二进制镜像的区别，以及链接脚本对内存布局、入口地址和段对齐的控制作用。
3. 理解 QEMU、OpenSBI 与 ucore 内核之间的启动关系。
4. 掌握使用 QEMU 和 GDB 调试裸机 RISC-V 程序的基本方法。
5. 通过 AI 辅助分析 Makefile、链接脚本、反汇编和调试结果，并对结论进行人工验证。

---

## 二、实验环境

### 2.1 硬件与宿主环境

| 项目 | 实际环境 |
|------|----------|
| 宿主操作系统 | Windows，WSL 2 |
| Linux 发行版 | Ubuntu 24.04 LTS |
| WSL 安装位置 | `D:\WSL\Ubuntu-24.04` |
| Linux 用户 | `lenovo` |
| 实验目录 | `/home/lenovo/os-labs/lab1` |
| 目标架构 | RISC-V 64 位 |

### 2.2 构建与调试工具

| 工具 | 已验证版本 | 用途 |
|------|------------|------|
| `riscv64-unknown-elf-gcc` | 13.2.0 | 将 C/汇编源文件交叉编译为 RISC-V 目标文件 |
| `riscv64-unknown-elf-binutils` | 与 Ubuntu 软件包配套 | 提供 `ld`、`objcopy`、`objdump`、`readelf`、`nm` 等工具 |
| GNU Make | 4.3 | 按 Makefile 组织构建流程 |
| QEMU | 8.2.2 | 模拟 RISC-V `virt` 平台 |
| GDB Multiarch | 15.1 | 连接 QEMU GDB Server，调试 RISC-V 内核 |

> **版本偏差说明：**小组分工文档建议/要求使用 QEMU 4.1.1，本实验实际使用 Ubuntu 24.04 软件源提供的 QEMU 8.2.2。由于新版本中课程原始 `-device loader` 启动方式没有把 OpenSBI 的 Next Address 设置为内核入口，本组将 `qemu` 和 `debug` 目标调整为 `-kernel $(UCOREIMG)`。调整后 OpenSBI 的 Next Address 为 `0x80200000`，内核输出和 GDB 验证均符合预期。该版本偏差应在提交前向助教确认；若课程明确拒绝其他版本，则仍需改回 QEMU 4.1.1。

### 2.3 AI 工具

| 成员 | AI 编程工具 | 底层模型 | 备注 |
|------|------------|----------|------|
| A：【2412101-张哲宇】 | Codex 桌面应用 | 【codex 5.5】 | 用于环境排错、Makefile 分析、GDB 步骤设计和报告整理；所有命令均由成员在本地复核 |
| B：【2410683-刘梓涵】 | zcode | glm5.3 | 用于镜像/引导特征分析、OpenSBI 加载过程分析、GDB 调试步骤设计与报错排查 |
| C：【学号-姓名】 | 【请填写】 | 【请填写】 | |

### 2.4 环境配置与验证过程

首先在 Windows 上安装 WSL 2，并将 Ubuntu 24.04 的虚拟磁盘安装到 D 盘，以避免占用系统盘。随后在 Ubuntu 中安装交叉编译器、QEMU、GDB 和 Make：

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    gcc-riscv64-unknown-elf \
    binutils-riscv64-unknown-elf \
    qemu-system-misc \
    gdb-multiarch \
    git unzip
```

使用下列命令完成阶段性版本检查：

```bash
riscv64-unknown-elf-gcc --version
qemu-system-riscv64 --version
gdb-multiarch --version
make --version
```

代码复制到 WSL 的 Linux 文件系统 `/home/lenovo/os-labs/lab1` 中编译，避免在 `/mnt/c` 或 `/mnt/d` 上直接构建导致权限、时间戳或文件系统语义差异。

环境版本验证结果如下：

![Lab 1 实验环境与工具版本](./images/lab1_env_versions.png)

---

## 三、实验整体逻辑分析

> 本节由 B 负责。

### 2.1 本章节的逻辑主线

本章围绕一个问题展开：**计算机上电之后，控制权是怎样一步步交到我们自己写的代码手里的？**

关键矛盾在于：操作系统必须被加载到内存才能执行，但"把操作系统加载到内存"这件事本身无法由操作系统自己完成——就像人不能拽着自己的头发把自己提离地面。而内存掉电即失，操作系统不能存在内存里；要放在掉电不丢失的设备上，可 CPU 读取这类设备又需要驱动程序，而驱动程序本身也存在这类设备上。这就形成了鸡生蛋、蛋生鸡的循环。

前人用一块"有 memory 接口、但掉电不丢失"的固件打破了这个循环。在 RISC-V 上，这块固件就是 **OpenSBI**：它随 QEMU 一起提供，运行在 M 态，完成最基本的硬件初始化后把控制权交给操作系统。

因此本实验的主线可以概括为一条地址链：

```text
0x00001000    复位向量 —— 上电后执行的第一条指令
0x80000000    OpenSBI 固件 —— 完成最基本的硬件初始化
0x80200000    我们的内核 —— 从 kern_entry 开始执行
```

为了让"被跳到 0x80200000 就能正确运行"这一前提成立，链接脚本、镜像格式、内核栈的建立、BSS 的清零必须环环相扣，这正是本章要逐一验证的内容。

### 2.2 功能的逐步实现

本章没有要求补写新的内核功能，而是按"先能编译、再能装载、然后能建立运行环境、最后能输出并被验证"的顺序逐步搭建：

1. **先让源码能变成镜像** —— 为什么首先做这个？
   后面所有验证都以产物正确为前提。用交叉工具链把 `.c`/`.S` 编译成 `.o`，再由链接脚本链接成 ELF，最后用 `objcopy` 压成线性 bin。产出的 `bin/ucore.img` 是后续所有环节的输入。

2. **再让镜像被装到约定的地址** —— 为什么接着做这个？
   链接脚本把 `BASE_ADDRESS` 定为 `0x80200000`，并让入口代码排在镜像最前面。只有装载地址与引导方的跳转目标一致，"被跳转过去"才不会跑飞。这一步由 QEMU 在虚拟机初始化阶段完成。

3. **然后让内核建立自己的运行环境** —— 为什么然后做这个？
   汇编入口 `kern_entry` 接手时，`sp` 仍是引导方留下的值。第一步必须把 `sp` 换到内核自己的栈（`bootstacktop`）上，C 代码才有可用的调用栈；随后 `kern_init` 清零 BSS，保证未初始化的全局变量初值为 0。

4. **最后让内核能输出，并用 GDB 验证整条链** —— 为什么最后做这个？
   输出是唯一能证明"内核真的在跑"的可见信号。裸机环境没有 libc，只能通过 `ecall` 调用 OpenSBI 提供的字符输出接口，再逐层封装成 `cprintf`。有了输出，再配合 GDB 在三个关键地址下断点，就能把"编译 → 装载 → 执行 → 输出"整条链验证闭环。

---

## 四、实验内容与实现

### 练习 1-1：理解通过 make 生成执行文件的过程

**负责人：** 2412101-张哲宇

#### 4.1.1 构建目标和总体依赖关系

Lab 1 没有要求补写新的内核功能，主要任务是理解并验证最小内核的构建和启动过程。执行 `make` 时，默认目标最终依赖 `bin/ucore.img`，其构建链为：

```text
.c / .S 源文件
    |
    | riscv64-unknown-elf-gcc -c
    v
obj/.../*.o
    |
    | riscv64-unknown-elf-ld -T tools/kernel.ld
    v
bin/kernel (ELF)
    |
    | riscv64-unknown-elf-objcopy --strip-all -O binary
    v
bin/ucore.img (纯二进制镜像)
```

同时，链接 `bin/kernel` 后还会生成：

```text
obj/kernel.asm  带源代码的反汇编结果
obj/kernel.sym  内核符号表
```

#### 4.1.2 源文件发现与目标文件命名

`Makefile` 通过 `tools/function.mk` 中的函数生成编译规则：

```make
listf = $(filter $(if $(2),$(addprefix %.,$(2)),%),\
          $(wildcard $(addsuffix $(SLASH)*,$(1))))
```

`listf` 枚举指定目录下符合后缀要求的文件。主 Makefile 定义：

```make
CTYPE := c S
```

因此 `.c` 和 `.S` 文件都会参与构建。

`toobj` 将源文件名映射到 `obj/` 下的目标文件：

```make
toobj = $(addprefix $(OBJDIR)$(SLASH)$(if $(2),$(2)$(SLASH)),\
        $(addsuffix .o,$(basename $(1))))
```

例如：

```text
kern/init/init.c   -> obj/kern/init/init.o
kern/init/entry.S  -> obj/kern/init/entry.o
libs/sbi.c         -> obj/libs/sbi.o
```

构建系统把 `libs/` 与 `kern/` 的目标文件分别加入 packet，最后由：

```make
KOBJS = $(call read_packet,kernel libs)
```

得到链接内核所需的全部目标文件。

#### 4.1.3 编译阶段

`tools/function.mk` 中真正的编译命令为：

```make
$(V)$(2) -I$(dir $(1)) $(3) -c $< -o $@
```

代入主 Makefile 中的变量后，核心形式为：

```bash
riscv64-unknown-elf-gcc [头文件路径和 CFLAGS] -c 源文件 -o 目标文件
```

各参数含义如下：

| 参数 | 含义 |
|------|------|
| `riscv64-unknown-elf-gcc` | 面向 RISC-V 裸机环境的交叉编译器 |
| `-I<dir>` | 添加头文件搜索目录 |
| `-mcmodel=medany` | 使用适合内核的中等代码模型，使代码可在较大地址范围内运行 |
| `-std=gnu99` | 采用 GNU C99 语言标准 |
| `-Wno-unused` | 不报告未使用项警告 |
| `-Werror` | 将警告视为错误 |
| `-fno-builtin` | 不把普通函数调用擅自替换为编译器内建实现 |
| `-Wall` | 开启常用警告 |
| `-O2` | 启用二级优化 |
| `-nostdinc` | 不使用宿主系统的标准头文件目录 |
| `-fno-stack-protector` | 关闭宿主环境栈保护插桩，避免引入内核尚未实现的运行库符号 |
| `-ffunction-sections` | 每个函数放入独立 section，便于链接时删除未使用代码 |
| `-fdata-sections` | 每个数据对象放入独立 section |
| `-g` | 保留调试信息，供 GDB 使用 |
| `-c` | 只编译/汇编，不执行链接 |
| `-o` | 指定输出目标文件 |

构建实测输出为：

```text
+ cc kern/init/entry.S
+ cc kern/init/init.c
+ cc kern/libs/stdio.c
+ cc kern/driver/console.c
+ cc libs/printfmt.c
+ cc libs/readline.c
+ cc libs/sbi.c
+ cc libs/string.c
```

#### 4.1.4 链接 ELF 内核

主 Makefile 中的链接命令为：

```make
$(LD) $(LDFLAGS) -T tools/kernel.ld -o $@ $(KOBJS)
```

实际核心形式为：

```bash
riscv64-unknown-elf-ld \
    -m elf64lriscv \
    -nostdlib \
    --gc-sections \
    -T tools/kernel.ld \
    -o bin/kernel \
    $(KOBJS)
```

| 参数 | 含义 |
|------|------|
| `-m elf64lriscv` | 生成 64 位小端 RISC-V ELF |
| `-nostdlib` | 不链接宿主系统标准库和启动文件 |
| `--gc-sections` | 删除没有被引用的独立函数/数据 section |
| `-T tools/kernel.ld` | 使用实验提供的链接脚本 |
| `-o bin/kernel` | 生成 ELF 内核文件 |
| `$(KOBJS)` | 所有参与链接的内核和库目标文件 |

链接脚本指定：

```ld
OUTPUT_ARCH(riscv)
ENTRY(kern_entry)
BASE_ADDRESS = 0x80200000;
```

因此 `bin/kernel` 的目标架构为 RISC-V，入口符号为 `kern_entry`，入口地址为 `0x80200000`。ELF 文件保留段表、符号表和调试信息，可以被 `readelf`、`objdump` 与 GDB 识别。

#### 4.1.5 生成反汇编和符号表

链接成功后执行：

```make
$(OBJDUMP) -S bin/kernel > obj/kernel.asm
```

其中 `-S` 将源代码与反汇编混合显示，便于将 C/汇编源码与真实机器指令对应。

符号表生成命令为：

```make
$(OBJDUMP) -t bin/kernel |
$(SED) '1,/SYMBOL TABLE/d; s/ .* / /; /^$/d' > obj/kernel.sym
```

`objdump -t` 输出符号表，后续 `sed` 删除标题、空行并压缩字段，得到便于查看的 `obj/kernel.sym`。

#### 4.1.6 从 ELF 转换为纯二进制镜像

最终镜像的构建规则为：

```make
$(OBJCOPY) $(kernel) --strip-all -O binary $@
```

实际命令为：

```bash
riscv64-unknown-elf-objcopy \
    bin/kernel \
    --strip-all \
    -O binary \
    bin/ucore.img
```

参数含义：

| 参数 | 含义 |
|------|------|
| `bin/kernel` | 输入 ELF 内核 |
| `--strip-all` | 删除符号和重定位等非运行必需信息 |
| `-O binary` | 指定输出为原始二进制格式 |
| `bin/ucore.img` | QEMU 加载的内核镜像 |

#### 4.1.7 ELF 与纯 bin 的区别

| 对比项 | `bin/kernel`（ELF） | `bin/ucore.img`（纯 bin） |
|--------|----------------------|---------------------------|
| 文件结构 | 有 ELF 头、程序头、section、符号与调试信息 | 基本只有需要装入内存的字节 |
| 是否记录入口地址 | 是 | 否 |
| 是否记录各段装载地址 | 是 | 否 |
| GDB/反汇编支持 | 可直接读取符号和源码信息 | 缺少符号与结构信息 |
| 主要用途 | 链接检查、反汇编、符号解析、GDB 调试 | 由 QEMU loader 按指定地址直接放入内存 |
| 实测大小 | 约 44 KiB | 约 16 KiB |

ELF 比纯 bin 大，是因为 ELF 还保存文件格式元数据、符号和调试信息；`.bss` 一般只在 ELF 中记录所需内存大小，不保存大段零字节。`objcopy` 这一步不能省略：课程原始 QEMU 命令使用 loader 将 `ucore.img` 当作无格式字节流装入 `0x80200000`，需要的是纯二进制镜像而不是完整 ELF 文件。

#### 4.1.8 make 的最终结果

实测执行：

```bash
make clean
make
```

成功生成：

```text
bin/kernel      约 44 KiB
bin/ucore.img   约 16 KiB
```

编译和链接过程没有出现错误。执行 `make qemu` 后，内核最终输出：

```text
(THU.CST) os is loading ...
```

这表明源文件编译、ELF 链接、镜像转换、加载和内核入口执行形成了完整闭环。

### 练习 1-2：逐行分析 `tools/kernel.ld`

**负责人：** C【学号-姓名】

> 待 C 合并正式答案。至少应逐行说明 `OUTPUT_ARCH`、`ENTRY`、`BASE_ADDRESS`、各 section、`ALIGN(0x1000)`、`etext`、`edata`、`end` 和 `/DISCARD/`。

### 练习 1-3：符合规范的镜像/引导特征

**负责人：** 【2410683-刘梓涵】

一个镜像要被 OpenSBI / QEMU 正确引导，需要同时满足下列几项约定。它们分别由链接脚本、镜像转换命令和启动参数共同保证。

**（1）有明确的入口符号**

`tools/kernel.ld` 开头两行：

```ld
OUTPUT_ARCH(riscv)     /* 目标架构为 riscv */
ENTRY(kern_entry)      /* 指定 ELF 入口点符号 */
```

`ENTRY(kern_entry)` 要求链接产物中存在名为 `kern_entry` 的符号，它由 `kern/init/entry.S` 用 `.globl kern_entry` 导出。两者必须一致，否则镜像没有可执行的起点。

**（2）装载基址与引导方约定的跳转地址一致**

```ld
BASE_ADDRESS = 0x80200000;
...
. = BASE_ADDRESS;      /* 定位计数器置为基址 */
```

`. = BASE_ADDRESS` 把定位计数器置为 `0x80200000`，即 `.text` 段从该地址开始排布。而 OpenSBI 固定跳到 `0x80200000` 执行。两者相同，代码才能在"被跳转到的那个位置"上正确运行。

**（3）入口代码位于镜像最前面**

`.text` 输出段把 `.text.kern_entry` 列为第一个输入模式：

```ld
.text : {
    *(.text.kern_entry .text .stub .text.* .gnu.linkonce.t.*)
}
```

排在首位的 `.text.kern_entry` 决定入口节位于整个 `.text` 的最始处，也就是 `BASE_ADDRESS`。

> 实测：`kern_entry = 0x80200000`，与镜像起始地址一致（见 GDB 调试体验一节的实测数据）。

**（4）关键位置按页对齐**

```ld
. = ALIGN(0x1000);     /* 数据段起始按 4 KiB 对齐 */
```

`0x1000 = 4096 = PGSIZE`（定义在 `kern/mm/mmu.h`）。数据段起始按页对齐，是为了后续分页机制能够以页为单位映射。

内核栈也要求对齐，`kern/init/entry.S` 中：

```assembly
.section .data
    .align PGSHIFT      /* PGSHIFT = 12，即 2^12 = 4096 字节对齐 */
    .global bootstack
bootstack:
    .space KSTACKSIZE   /* KSTACKPAGE(2) × PGSIZE(4096) = 8192 字节 */
    .global bootstacktop
bootstacktop:
```

> 实测：`bootstack = 0x80201000`、`bootstacktop = 0x80203000`，两者都是 4 KiB 对齐，差值 `0x2000 = 8192` 字节。

**（5）镜像为线性纯二进制**

```make
$(OBJCOPY) bin/kernel --strip-all -O binary bin/ucore.img
```

`objcopy -O binary` 去掉 ELF 头与节头，把各段按链接地址压成一段线性数据。这样"文件偏移 ↔ 内存地址"一一对应，只要整体装到 `0x80200000`，各段就都落在链接时确定的位置上。这正是引导方最容易理解的形式（详见练习 2）。

**小结**

符合规范的镜像 = **入口符号明确** + **装载基址与引导方约定相同** + **入口代码在镜像最前** + **关键位置页对齐** + **线性 bin 格式**。五项齐备，镜像才能被正确装载并执行。

### 练习 2：OpenSBI 与 bin 格式内核的加载过程

**负责人：** 【2410683-刘梓涵】

> **结论先行：本实验中，无论"读硬盘扇区"还是"加载内核"，实际都不是 OpenSBI 执行的。**
> 两者都由 QEMU 在虚拟机初始化阶段完成，OpenSBI 只负责最后的跳转。

**（1）OpenSBI 如何读取硬盘扇区？——它并不读**

QEMU 的启动参数里没有任何块设备（没有 `-drive`、`-hda`、`-device virtio-blk` 等），guest 中根本不存在"硬盘"这个设备。内核镜像 `bin/ucore.img` 是宿主机上的普通文件：

- QEMU 在**虚拟机初始化阶段**（guest CPU 尚未开始执行时），用宿主机的文件系统把该文件读入宿主内存；
- 再把它拷贝到 guest 物理内存的 `0x80200000`；
- 从 guest 的视角看，就是"内存里已经躺好了镜像"，不存在逐扇区读取的过程。

课程指导书也明确指出：本实验中 OpenSBI "读硬盘并加载内核"的作用并没有真正发挥，而是使用了 QEMU 的加载器把内核放到指定的内存位置上。

**（2）OpenSBI 如何加载 bin 格式的 OS？——它只负责跳转**

完整启动链路：

| 步骤 | 执行者 | 动作 |
|------|--------|------|
| 1 | QEMU | 把 OpenSBI 固件放到 `0x80000000`（`-bios default`） |
| 2 | QEMU | 把 `ucore.img` 放到 `0x80200000` |
| 3 | CPU | 复位，PC = `0x1000` |
| 4 | 复位向量 | 跳转到 `0x80000000`，开始执行 OpenSBI |
| 5 | OpenSBI | 在 M 态完成最基本的硬件初始化 |
| 6 | OpenSBI | 把 PC 设为 `0x80200000`，交权给内核 |
| 7 | 内核 | 从 `kern_entry` 开始执行 |

因此严格来说，"加载"这一动作是第 2 步由 QEMU 完成的；OpenSBI 做的是第 5、6 步。

**（3）为什么必须转成 bin，而不能直接用 ELF？**

ELF 文件包含 ELF 头和 program header，必须解析 program header 才能知道每个段应当放到哪里；而引导方并不解析 ELF。`objcopy -O binary` 产出的 bin 是线性映像，只需整体放到一个约定地址即可，正好匹配"固定跳到 `0x80200000`"这一约定。

bin 的代价是体积：`.bss` 段在 ELF 中只记录起止地址（不占文件空间），转成 bin 后会变成实打实的若干零字节，所以 bin 通常比 ELF 大。

**（4）版本差异与实测结果（重要）**

上述"OpenSBI 固定跳到 `0x80200000`"是 **QEMU 4.1.1（课程指定版本）** 的行为。本组阶段性环境使用 Ubuntu 24.04 自带的 QEMU 8.2.2，观察到了不同表现：

| 启动参数 | OpenSBI 报告的 Domain0 Next Address | 结果 |
|---------|-----------------------------------|------|
| `-device loader,file=$(UCOREIMG),addr=0x80200000` | `0x0000000000000000` | 内核不执行，无输出 |
| `-kernel $(UCOREIMG)` | `0x0000000080200000` | 正常输出 `(THU.CST) os is loading ...` |

原因：新版 OpenSBI 的跳转地址不再由固件写死，而是由 QEMU 通过启动参数传入；`-device loader` 不会设置该字段，`-kernel` 会把它设为 virt 机器的默认内核装载地址 `0x80200000`。据此本组把 Makefile 的 `qemu` / `debug` 目标调整为 `-kernel $(UCOREIMG)`。

> ⚠️ **该版本偏差与 Makefile 修改需向助教确认。** 课程明确指定 QEMU 4.1.1；若要求严格一致，应改用 4.1.1 并还原 Makefile 的原始写法（`-device loader,file=...,addr=0x80200000`）。

### SBI 到 stdio 的输出调用链

**负责人：** C【学号-姓名】

> 待 C 合并正式答案。建议按照 `cprintf -> vcprintf -> vprintfmt -> cputch -> cons_putc -> sbi_console_putchar -> sbi_call -> ecall -> OpenSBI -> UART` 组织。

### GDB 调试体验

**负责人：** 【2410683-刘梓涵】

**（1）调试方式**

```bash
# 终端 1：以调试模式启动 QEMU
make debug      # 即 -s -S：启动后暂停，并监听 :1234
# 终端 2：连接调试桩
make gdb
```

`-S` 让 QEMU 启动后立即暂停、不执行任何指令；`-s` 是 `-gdb tcp::1234` 的简写。这样可以在内核执行第一条指令之前就接管它。连接命令等价于：

```bash
riscv64-unknown-elf-gdb \
  -ex 'file bin/kernel' \
  -ex 'set arch riscv:rv64' \
  -ex 'target remote localhost:1234'
```

**（2）三个关键地址**

```
0x00001000    RISC-V 复位向量 —— 上电后执行的第一条指令
0x80000000    OpenSBI 固件基址 —— 完成最基本的硬件初始化
0x80200000    内核链接基址（BASE_ADDRESS）—— 我们自己的代码从这里开始
```

**（3）操作步骤与实测结果**

| # | 操作 | 观察结果 |
|---|------|---------|
| 1 | `b *0x80200000` → `c` | PC 落在 `kern_entry`（`0x80200000`） |
| 2 | `p/x $sp` | `0x80046eb0` —— 进入 `kern_entry` 时仍是引导方移交过来的栈 |
| 3 | `p/x &bootstack` / `p/x &bootstacktop` | `0x80201000` / `0x80203000` |
| 4 | `si`（单步执行 `la sp, bootstacktop`） | `sp` 变为 `0x80203000` |
| 5 | `p $sp == &bootstacktop` | `1`（相等） |
| 6 | `p/x kern_init` | `0x8020000a` |
| 7 | `b *0x8020000a` → `c` | 进入 C 语言入口 `kern_init` |
| 8 | `p/x $pc` | `0x8020003a`（`while(1)` 所在处） |
| 9 | `x/i $pc` | `j 0x8020003a` —— 自跳转，进入死循环 |

实测数据汇总：

```text
kern_entry      = 0x80200000
进入 kern_entry 时 sp = 0x80046eb0
bootstack       = 0x80201000
bootstacktop    = 0x80203000
栈大小          = 8192 bytes
执行 la sp, bootstacktop 后 sp = 0x80203000
$sp == &bootstacktop 的结果为 1
kern_init       = 0x8020000a
while (1)       = 0x8020003a
循环指令        = j 0x8020003a
```

**（4）结论**

1. `sp` 由 `0x80046eb0` 变为 `0x80203000`，说明 `kern/init/entry.S` 的第一条指令 `la sp, bootstacktop` 确实生效，内核已切换到自己的栈上。
2. `bootstacktop - bootstack = 0x2000 = 8192 = KSTACKPAGE(2) × PGSIZE(4096)`，与头文件中的定义完全一致，验证了栈的大小与页对齐。
3. `kern_entry` 位于 `0x80200000`，即镜像起始处，印证了练习 1-3 中"入口代码位于镜像最前面"这一特征。
4. 内核最终停在 `j 0x8020003a` 的自跳转指令上，与 `kern/init/init.c` 中 `while (1);` 的语义一致，说明"汇编入口 → C 入口"的移交完整走通。

**（5）过程中遇到的问题**

**问题：GDB 多行命令粘贴解析失败**

一次粘贴多条命令时出现：

```text
Junk after item "riscv:rv64"
No symbol "p" in current context.
```

原因是多行文本被终端/GDB 合并进了同一条命令。改为逐条输入 `set architecture`、`target remote`、`break`、`continue`、`si`、`p` 后恢复正常。

---

## 五、测试与验证

### 5.1 编译测试

执行：

```bash
cd ~/os-labs/lab1
make clean
make
```

实际输出的关键部分：

```text
+ cc kern/init/entry.S
+ cc kern/init/init.c
+ cc kern/libs/stdio.c
+ cc kern/driver/console.c
+ cc libs/printfmt.c
+ cc libs/readline.c
+ cc libs/sbi.c
+ cc libs/string.c
+ ld bin/kernel
riscv64-unknown-elf-objcopy bin/kernel --strip-all -O binary bin/ucore.img
```

结果：编译、链接和镜像转换均成功。

编译、产物格式和入口地址验证结果如下：

![Lab 1 编译结果](./images/lab1_make.png)

### 5.2 QEMU 运行测试

本实验实际使用 QEMU 8.2.2。由于该版本与课程原始 loader 参数的行为存在差异，将启动参数调整为：

```make
-kernel $(UCOREIMG)
```

随后 OpenSBI 显示：

```text
Domain0 Next Address      : 0x0000000080200000
```

并成功输出：

```text
(THU.CST) os is loading ...
```

这证明内核镜像能够在 `0x80200000` 开始执行。报告与代码均如实保留该兼容性修改，不将实际环境误写为 QEMU 4.1.1。提交前仍建议取得助教对 QEMU 8.2.2 的确认。

QEMU 运行结果如下：

![Lab 1 QEMU 运行结果](./images/lab1_make_qemu.png)

### 5.3 GDB 验证

通过 QEMU GDB Server 与 `gdb-multiarch` 调试，确认：

1. OpenSBI 最终进入 `0x80200000` 的 `kern_entry`。
2. `bootstacktop - bootstack = 8192`，即内核栈大小为 8 KiB。
3. 执行 `la sp, bootstacktop` 后，`sp = 0x80203000`，比较 `$sp == &bootstacktop` 的结果为 `1`。
4. `kern_init` 位于 `0x8020000a`。
5. 输出启动信息后，内核在 `0x8020003a` 执行自跳转，对应源码的 `while (1)`。

内核入口和内核栈验证结果如下：

![内核入口与内核栈验证](./images/lab1_gdb_kernel.png)

若 B 按分工补充完整的三跳调试过程，还应增加：

```markdown
![复位向量断点](./images/lab1_gdb_0x1000.png)
![OpenSBI 入口断点](./images/lab1_gdb_opensbi.png)
![内核运行输出](./images/lab1_gdb_run.png)
```

### 5.4 `make grade` 说明

实验包中缺少 `tools/grade.sh`，但 Makefile 的 `grade` 目标会执行：

```make
$(SH) tools/grade.sh
```

因此当前材料无法完成 `make grade`。提交前应向助教确认：

1. Lab 1 是否不要求 `make grade`；
2. 是否需要补发 `tools/grade.sh`；
3. 报告中是否可以用编译、QEMU 输出和 GDB 结果替代 grade 截图。

在得到答复前，不应伪造 `make grade` 成功截图。

---

## 六、实验总结与收获

> 本节由 C 负责。可结合以下要点完成：

1. Makefile 不只是命令集合，还编码了源文件发现、依赖生成、目标文件分组、链接和镜像转换的依赖图。
2. ELF 文件包含入口、段、符号和调试信息；纯 bin 不自描述，必须由加载者提供装载地址。
3. 裸机内核不能依赖宿主标准库，编译和链接时需要关闭默认运行时，并由内核自己建立栈、清零 BSS。
4. 链接地址、QEMU 装载地址与 OpenSBI 跳转地址必须一致。
5. AI 可以快速给出命令和分析框架，但版本要求、真实输出和课程材料必须由成员本地复核。
