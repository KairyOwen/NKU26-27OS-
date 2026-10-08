# 操作系统实验报告

## 实验基本信息

| 项目 | 内容 |
|------|------|
| **实验名称** | Lab 1：比麻雀更小的麻雀（最小可执行内核） |
| **小组成员** | 【2412101-张哲宇】、【请填写：学号-姓名】、【请填写：学号-姓名】 |
| **完成日期** | 2026-10-8 |

### 小组分工

| 成员 | 负责的练习/模块 |
|------|----------------|
| A：【2412101-张哲宇】 | 环境搭建与验证、练习 1-1（Makefile 构建过程）、测试与验证、仓库与提交管理 |
| B：【学号-姓名】 | 练习 1-3、练习 2、GDB 调试体验、实验整体逻辑分析 |
| C：【学号-姓名】 | 练习 1-2（链接脚本）、SBI 到 stdio 调用链、实验目的与总结、全文格式终检 |

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
| B：【学号-姓名】 | 【请填写】 | 【请填写】 | |
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

> 本节由 B 负责。建议围绕以下主线展开并替换本提示：
>
> `QEMU 复位向量 0x1000 -> OpenSBI 0x80000000 -> 内核入口 0x80200000 -> 设置内核栈 -> kern_init -> 清零 BSS -> SBI 控制台输出 -> while (1)`

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

**负责人：** B【学号-姓名】

> 待 B 合并正式答案。应从链接脚本、`0x80200000` 装载基址和页对齐三个角度说明。

### 练习 2：OpenSBI 与 bin 格式内核的加载过程

**负责人：** B【学号-姓名】

> 待 B 合并正式答案。应特别说明本实验原始 Makefile 使用 QEMU `-device loader,file=...,addr=0x80200000` 直接将镜像放入内存，并非 OpenSBI 自己从磁盘逐扇区读取内核。

### SBI 到 stdio 的输出调用链

**负责人：** C【学号-姓名】

> 待 C 合并正式答案。建议按照 `cprintf -> vcprintf -> vprintfmt -> cputch -> cons_putc -> sbi_console_putchar -> sbi_call -> ecall -> OpenSBI -> UART` 组织。

### GDB 调试体验

**负责人：** B【学号-姓名】

阶段性调试已经获得以下真实结果，可交给 B 复核并纳入正式章节：

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
