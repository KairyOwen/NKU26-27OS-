# 操作系统实验报告

## 实验基本信息

| 项目 | 内容 |
|------|------|
| **实验名称** | Lab 1：比麻雀更小的麻雀（最小可执行内核） |
| **小组成员** | 2412101-张哲宇、2410683-刘梓涵、2411310-李镕吉 |
| **完成日期** | 2026-10-10 |

### 小组分工

练习如何分工？

| 成员 | 负责的练习/模块 |
|------|----------------|
| A：2412101-张哲宇 | 环境搭建与验证、练习 1-1、测试证据、仓库与提交 |
| B：2410683-刘梓涵 | 练习 1-3、练习 2、GDB 调试体验、整体逻辑分析 |
| C：2411310-李镕吉 | 练习 1-2、SBI 到 stdio 调用链、报告与提示词汇总 |

实验报告如何分工？

| 成员 | 负责的报告章节 |
|------|---------------|
| A | 二、实验环境；四（练习 1-1）；五、测试与验证 |
| B | 三、实验整体逻辑分析；四（练习 1-3、练习 2、GDB） |
| C | 一、实验目的；四（练习 1-2、输出链）；六、实验总结与收获；格式终检 |

本报告在 GitHub 已有小组分析的基础上整合修订，以 2026-10-09 拍摄的 QEMU 4.1.1 最终截图和实际终端记录为验证依据。Lab 1 是分析与验证实验，没有新增内核功能的编程任务。

---

## 一、实验目的

1. 理解交叉编译、链接和格式转换生成内核镜像的过程。
2. 理解链接地址、装载地址、入口地址及链接脚本的段布局和对齐。
3. 区分 QEMU 装载、OpenSBI 初始化与控制权移交、内核自身的运行时初始化。
4. 使用 GDB 观察入口执行、内核栈和无限循环，将源码与实际机器指令对应。
5. 分析格式化输出经 SBI 到终端的调用链，以实际结果复核 AI 分析。

---

## 二、实验环境

### 2.1 运行与构建环境

| 项目 | 最终验证环境 |
|------|--------------|
| 宿主环境 | Windows、WSL 2 |
| Linux | Ubuntu 24.04.5 LTS |
| 实验目录 | Ubuntu 用户目录下的 ~/os-labs/lab1 |
| 目标平台 | RISC-V 64 位，QEMU virt |
| 交叉编译器 | riscv64-unknown-elf-gcc 13.2.0 |
| 二进制工具 | riscv64-unknown-elf 的 ld、objcopy、objdump、readelf 等 |
| QEMU | **4.1.1，源码编译** |
| GDB | gdb-multiarch 15.1 |
| Make | GNU Make 4.3 |
| 固件 | OpenSBI v0.4，Runtime SBI Version 0.1 |

源码构建目录为 `~/src/qemu-4.1.1-build`。已通过 configure、make 编译得到 riscv64-softmmu/qemu-system-riscv64，版本输出为 4.1.1，退出码为 0。最终环境截图显示实际使用的安装程序：

```text
/home/lenovo/opt/qemu-4.1.1/bin/qemu-system-riscv64
QEMU emulator version 4.1.1
```

完成源码安装后，用以下命令选择和检查工具：

```bash
export PATH="$HOME/opt/qemu-4.1.1/bin:$PATH"
which qemu-system-riscv64
qemu-system-riscv64 --version
riscv64-unknown-elf-gcc --version
gdb-multiarch --version
make --version
```

QEMU 8.2.2 曾用于阶段性排错，最终已切换到课程指定的源码编译 QEMU 4.1.1，恢复原始 loader 参数并重新验证。最终截图见第五节。

### 2.2 AI 工具

你们使用的 AI 工具：

| 成员 | AI 编程工具 | 底层模型 | 备注 |
|------|------------|---------|------|
| A：2412101-张哲宇 | Codex 桌面应用 | 前期组内记录为 codex 5.5；本次整合为 GPT-6 | 环境排错、构建分析、调试指导、报告核对和提交 |
| B：2410683-刘梓涵 | zcode | glm5.3（组员记录） | 镜像、启动链和 GDB 分析 |
| C：2411310-李镕吉 | ClaudeCode | kimi-k2.6（组员记录） | 链接脚本、输出链和文档整理 |

AI 编程工具指应用或客户端，底层模型指其中使用的语言模型。B、C 信息保留自仓库报告，未在本次独立核验客户端设置。提示词及迭代汇总见 [prompt.md](./prompt.md)。

---

## 三、实验整体逻辑分析

### 2.1 本章节的逻辑主线

本实验围绕“启动后控制权怎样交到最小内核”展开。源码需要变成目标平台指令，按约定装入内存；进入 C 函数前必须建立栈，随后初始化数据并输出。最终以终端和 GDB 验证：

```text
源码 -> 目标文件 -> ELF -> bin -> QEMU 装载
0x1000 复位代码 -> 0x80000000 OpenSBI -> 0x80200000 kern_entry
 -> 建立栈 -> kern_init -> 清零 BSS -> cprintf -> SBI -> 终端 -> while (1)
```

QEMU 在虚拟机初始化阶段准备固件和内核；OpenSBI 在 M-mode 初始化并移交至 S-mode 内核。本实验没有 OpenSBI 从磁盘逐扇区读取内核的过程。

### 2.2 功能的逐步实现

1. **先验证构建**：交叉编译得到目标文件，链接生成 ELF，再转换 bin，后续步骤依赖这些产物。
2. **再核对地址**：链接布局、装载地址和跳转目标一致，才能执行正确指令。
3. **随后建立运行环境**：入口设置 sp，C 入口清零 BSS，满足栈和全局变量初值要求。
4. **最后验证输出与状态**：启动字符串证明内核运行；GDB 检查入口、栈和循环，与源码形成对应。

---

## 四、实验内容与实现

### 练习 1-1：理解通过 make 生成执行文件的过程

**负责人：** 2412101-张哲宇

#### 功能描述与涉及文件

分析 Makefile 和 tools/function.mk，没有需要新增的函数。最终目标为 bin/ucore.img，bin/kernel 用于符号调试。

#### 构建过程、命令与参数

`CTYPE := c S` 指定源文件后缀；listf 枚举源文件，toobj 映射到 obj 目录，add_files_cc 生成规则。`KOBJS = $(call read_packet,kernel libs)` 汇总目标文件。默认目标 TARGETS 由辅助函数汇总生成。

```text
kern/init/entry.S -> obj/kern/init/entry.o
kern/init/init.c  -> obj/kern/init/init.o
libs/sbi.c        -> obj/libs/sbi.o
```

**第一步：编译和汇编。** 辅助规则核心命令：

```make
$(2) -I$(dir $(1)) $(3) -c $< -o $@
```

$(2) 是编译器，$(3) 是选项，$< 为源文件，$@ 为目标；-c 只编译/汇编，-o 指定输出。

| 选项 | 作用 |
|------|------|
| -mcmodel=medany | PC 相对寻址代码模型；仍有约 ±2 GiB 的相对可达范围限制 |
| -std=gnu99 | GNU C99 |
| -Wall -Werror -Wno-unused | 常用警告、警告视为错误、抑制未使用项警告 |
| -O2 | 二级优化，源码行与指令不一定一一对应 |
| -fno-builtin | 避免依赖编译器内建函数替换 |
| -nostdinc、-I... | 不使用默认标准头文件目录，指定实验头文件 |
| -fno-stack-protector | 避免引入尚未提供的栈保护运行库 |
| -ffunction-sections -fdata-sections | 函数和数据进入独立 section，便于链接回收 |
| -g | 生成调试信息 |

**第二步：链接 ELF。**

```make
$(LD) $(LDFLAGS) -T tools/kernel.ld -o $@ $(KOBJS)
```

核心参数为 `-m elf64lriscv -nostdlib --gc-sections -T tools/kernel.ld -o bin/kernel`。-m 选择 64 位小端 RISC-V 链接仿真，-nostdlib 避免默认标准库搜索，--gc-sections 回收未引用 section，-T 指定脚本，-o 指定输出。启动文件和运行库也没有作为链接输入提供。

**第三步：生成反汇编和符号表。**

```make
$(OBJDUMP) -S bin/kernel > obj/kernel.asm
$(OBJDUMP) -t bin/kernel | $(SED) '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > obj/kernel.sym
```

-S 混合显示源码和反汇编；-t 输出符号表；sed 删除标题、空行并简化字段。Makefile 的 $$ 传给 shell 后成为 $。

**第四步：转换为 bin。**

```bash
riscv64-unknown-elf-objcopy bin/kernel --strip-all -O binary bin/ucore.img
```

--strip-all 移除符号和重定位信息；-O binary 指定原始二进制。转换输出可装载且有文件内容的区域，并保留相对地址间隙，不带 ELF 头和调试信息。

| 对比 | bin/kernel | bin/ucore.img |
|------|------------|---------------|
| 格式 | RISC-V 小端 ELF64 | 原始字节流 |
| 元信息 | 入口、段/节、符号和调试信息 | 无这些自描述信息 |
| 用途 | readelf、objdump、GDB | 按约定地址装入内存 |
| 最终截图 ls -lh | 43K | 13K |

43K、13K 是近似文件长度。此前 find 的 %k 显示 44 KB、16 KB 是磁盘分配量，不是同一指标。本实验选择 bin 配合显式地址加载，需要 objcopy；支持 ELF 的加载器则可直接解析 ELF。

#### 最终提示词

```markdown
依据实际 Makefile 和 tools/function.mk，逐条解释 .c/.S 到 obj/*.o、
bin/kernel、obj/kernel.asm、obj/kernel.sym、bin/ucore.img 的依赖、
命令和参数。区分 ELF 与 bin，用实际截图核对格式和入口，
不要把磁盘占用量当作文件长度。
```

#### 实现迭代过程

初次构建成功后补查格式和入口。最终截图确认 ELF64、RISC-V、入口 0x80200000；报告修正了文件长度与磁盘分配量的混用。本练习未新增内核代码。

### 练习 1-2：逐行分析 tools/kernel.ld

**负责人：** 2411310-李镕吉

#### 功能描述与逐行解释

脚本定义输出 section 布局及符号边界。以下按原文件顺序覆盖有效语句；注释提供说明，花括号划定块范围。

| 语句或连续块 | 含义 |
|-------------|------|
| OUTPUT_ARCH(riscv) | 输出架构为 RISC-V |
| ENTRY(kern_entry) | 将符号地址记录为 ELF 入口 |
| BASE_ADDRESS = 0x80200000; | 本实验内核链接基址 |
| SECTIONS { ... } | 输入到输出 section 的映射 |
| . = BASE_ADDRESS; | 设置位置计数器 |
| .text : { ... } | 输出代码段 |
| *(.text.kern_entry .text .stub .text.* .gnu.linkonce.t.*) | 收集匹配的入口、普通代码、桩和 linkonce 代码 section |
| PROVIDE(etext = .); | 在需要且无其他定义时提供代码末尾符号 |
| .rodata : { ... } | 输出只读数据段 |
| *(.rodata .rodata.* .gnu.linkonce.r.*) | 收集常量等只读数据 |
| . = ALIGN(0x1000); | 向上对齐到 4 KiB 边界 |
| .data : { ... } | 输出有文件内容的数据段 |
| *(.data) | 收集普通 data |
| *(.data.*) | 收集细分 data |
| .sdata : { ... } | 输出小数据段 |
| *(.sdata)、*(.sdata.*) | 收集小数据；是否用 gp 寻址取决于工具链和初始化 |
| PROVIDE(edata = .); | 已初始化数据末尾符号 |
| .bss : { ... } | 占用内存、通常无文件内容的零初始化区域 |
| *(.bss)、*(.bss.*) | 收集普通及细分 BSS |
| *(.sbss*) | 收集小型零初始化数据 |
| PROVIDE(end = .); | BSS 结束边界 |
| /DISCARD/ : { ... } | 丢弃匹配输入 section |
| *(.eh_frame .note.GNU-stack) | 丢弃异常/展开元数据和 GNU 栈属性标记 |

位置计数器描述链接布局，本脚本没有另设 AT 装载地址。页对齐有利于后续页映射和权限划分，但本实验尚未实现分页保护。

**入口核对：**实际 entry.S 使用 `.section .text,"ax",%progbits`，没有声明 .text.kern_entry。因此不能仅凭脚本匹配模式声称入口必定在最前；本次构建依赖 entry.o 链接顺序，并由 ELF 和 GDB 验证 kern_entry=0x80200000。

#### 与初始化函数的关系

```c
int kern_init(void) __attribute__((noreturn));
/* kern_init 中的实际初始化语句 */
extern char edata[], end[];
memset(edata, 0, end - edata);
```

edata、end 是链接器符号，不是分配出来的数组；清零范围覆盖 BSS 和可能的对齐间隙。etext 表示代码结束，init.c 没有直接引用。end 只是镜像边界，不能直接认定其后所有内存都可分配。

BSS 通常是 ELF NOBITS 区域，不保存对应零字节，正常 binary 转换也不会自动实体化整个 BSS。本实验 bootstack 在 entry.S 的 .data 中预留，不属于 BSS。

#### 最终提示词

```markdown
逐行解释实际 kernel.ld，结合 entry.S 和 init.c 核对入口 section、
链接顺序、PROVIDE、页对齐和 BSS 清零。区分源码与脚本设计意图，
不要推断未验证的 gp 初始化、空闲内存范围或分页保护。
```

#### 实现迭代过程

沿用组员脚本分析，复核 entry.S 后修正入口 section 描述，并修正 BSS 文件表示和边界用途。没有修改链接脚本或初始化函数。

### 练习 1-3：符合规范的镜像/引导特征

**负责人：** 2410683-刘梓涵

本实验镜像的规范是它与当前加载、启动方式的约定：

1. **架构正确**：指令属于目标 RISC-V 平台；ELF 检查显示 RISC-V。
2. **地址一致**：链接基址、loader 地址、OpenSBI 交权目标均为 0x80200000。
3. **执行起点正确**：bin 无入口元信息，固定跳到镜像起点时必须得到入口代码；本次 ELF/GDB 验证了这一点。
4. **布局和对齐合理**：数据段页对齐，entry.S 的 .align PGSHIFT 对齐栈；PGSHIFT=12，即 4096 字节。
5. **初始化完整**：进入 C 前建立栈，清零 BSS，提供裸机库函数。

实测 bootstack=0x80201000、bootstacktop=0x80203000，差值 0x2000=8192 字节。页对齐是本实验布局约定，不是所有镜像格式的普遍要求；这里也没有 x86 启动扇区的 0x55AA 签名要求。

#### 最终提示词

```markdown
结合 kernel.ld、entry.S、objcopy 和 QEMU 4.1.1 loader 参数，
解释镜像可正确引导的约定，区分链接、装载、入口地址，
说明 4 KiB 对齐、8 KiB 栈，用 ELF/GDB 证据验证。
```

#### 实现迭代过程

保留组员关于地址、对齐、bin 的分析，以最终截图核对入口和栈，纠正专用入口 section 已被本源码使用的推断。

### 练习 2：OpenSBI 与 bin 格式 OS 的启动过程

**负责人：** 2410683-刘梓涵

最终使用课程原始命令：

```bash
qemu-system-riscv64 \
    -machine virt \
    -nographic \
    -bios default \
    -device loader,file=bin/ucore.img,addr=0x80200000
```

| 参数 | 作用 |
|------|------|
| -machine virt | RISC-V virt 虚拟平台 |
| -nographic | 关闭图形显示，将串口/监控台接入终端 |
| -bios default | 使用该 QEMU 版本的默认固件 |
| -device loader,file=...,addr=... | 通用加载器将本实验 bin 放到指定客户机地址 |

**如何读扇区？**命令未配置存放内核的块设备。QEMU 读取宿主文件并准备客户机内存；OpenSBI 没有逐扇区读取 ucore.img。

**如何加载？**执行前 QEMU 已准备 0x80000000 的固件和 0x80200000 的内核。CPU 从 0x1000 复位代码跳入 OpenSBI；固件初始化 M-mode 环境，然后按该版本约定移交到 S-mode 内核。内核再建立栈、清零 BSS 和输出。

通用 loader 也支持识别部分可执行格式，包括 ELF；使用 bin 是本实验的构建选择，不能据此声称 QEMU 不解析 ELF。bin 的代价是缺少自描述信息，需要外部地址约定，不是“BSS 必然实体化而比 ELF 大”。

#### 最终提示词

```markdown
根据 QEMU 4.1.1 的 -bios default 和 -device loader 命令，
区分 QEMU 装载、复位代码、OpenSBI 初始化/交权和内核初始化。
回答是否有读硬盘扇区过程，不把宿主文件读取归因于 OpenSBI，
不把 bin 路径推广为 QEMU 不支持 ELF。
```

#### 实现迭代过程

QEMU 8.2.2 + OpenSBI v1.3 的 loader 启动曾只显示固件，终端 Next Address 为 0；临时 -kernel 路径可运行，用于定位版本差异。随后源码编译 QEMU 4.1.1，恢复 loader 并重测、截图。最终以 4.1.1 + OpenSBI v0.4 为准。

### 附加分析：SBI 到 stdio 的输出调用链

**负责人：** 2411310-李镕吉

#### 涉及函数与功能

```c
int cprintf(const char *fmt, ...);
int vcprintf(const char *fmt, va_list ap);
void vprintfmt(void (*putch)(int, void *), void *putdat,
               const char *fmt, va_list ap);
void cons_putc(int c);
void sbi_console_putchar(unsigned char ch);
uint64_t sbi_call(uint64_t sbi_type, uint64_t arg0,
                  uint64_t arg1, uint64_t arg2);
```

```text
kern_init -> cprintf -> vcprintf -> vprintfmt -> cputch
 -> cons_putc -> sbi_console_putchar -> sbi_call
 -> ecall -> OpenSBI -> UART -> QEMU 终端
```

cprintf 收集可变参数，vcprintf 建立计数，vprintfmt 解析格式并逐字符回调 cputch。cputch 输出并递增计数，cons_putc 交给 SBI。

此处使用 legacy SBI console putchar，调用号为 1。sbi_call 把调用号放入 a7/x17，参数放入 a0/x10、a1/x11、a2/x12，ecall 触发环境调用异常，OpenSBI 在 M-mode 处理后返回。固件 UART 支持完成实际输出。

使用 SBI 可减少驱动工作并复用固件接口。S-mode 并非架构上永远不能访问 UART；若平台映射和 PMP 等权限允许，也能直接操作 MMIO。不能将本实验的选择解释为普遍的硬件禁令。

#### 最终提示词

```markdown
依据 stdio.c、printfmt.c、console.c 和 sbi.c 解释 cprintf 到 UART，
标出格式化、回调、计数、legacy SBI 寄存器和 ecall 特权切换。
说明选择 SBI 的便利性，不声称所有 S-mode 内核都不能访问 UART。
```

#### 实现迭代过程

保留组员逐层分析，核对调用号和寄存器，修正直接设备访问的绝对化说明。没有新增 UART 驱动。

### 附加练习：GDB 调试体验

**负责人：** 2410683-刘梓涵

#### 操作步骤

终端一执行 make debug；-S 暂停 CPU，-s 开启默认 1234 端口。终端二执行：

```bash
gdb-multiarch bin/kernel
```

随后逐条输入：

```gdb
set architecture riscv:rv64
target remote localhost:1234
p/x $pc
break *0x80200000
continue
p/x $pc
p/x $sp
p/x &bootstack
p/x &bootstacktop
p/d (char *)&bootstacktop - (char *)&bootstack
si
si
p/x $sp
p $sp == &bootstacktop
```

Makefile 的 make gdb 使用 riscv64-unknown-elf-gdb；本次实际截图用 gdb-multiarch，复现步骤采用后者。

| 检查项 | 最终截图结果 |
|--------|--------------|
| 连接时 PC | 0x1000 |
| 内核入口 PC | 0x80200000 |
| 切换前 sp | 0x8001bd80 |
| bootstack | 0x80201000 |
| bootstacktop | 0x80203000 |
| 栈大小 | 8192 字节 |
| 两次 si 后 sp | 0x80203000 |
| sp == &bootstacktop | 1 |

la 是伪指令，本次展开为 auipc 和 mv，需要两次机器指令单步完成。

另有实际终端记录：继续运行后在 **GDB 窗口** Ctrl+C，PC=0x8020003a，反汇编为 `j 0x8020003a`，对应 while (1)。该循环结果来自终端记录，当前入口截图不包含它。0x80000000 为固件基址，但本次没有归档该地址单独命中断点的截图，也没有声称完成全部三处截图。

#### 最终提示词

```markdown
为 QEMU 4.1.1 和 gdb-multiarch 设计逐条步骤，验证复位 PC、内核入口、
bootstack、bootstacktop、两次 si 后 sp。解释 la 展开及 continue 后
如何在 GDB 中中断循环，区分截图证据与终端记录。
```

#### 实现迭代过程

多行粘贴曾触发 Junk after item "riscv:rv64"、No symbol "p"，改为逐条输入。continue 后没有提示符表示目标仍在运行，需要在 GDB 中 Ctrl+C。退出 QEMU 是另一操作：其终端可用 Ctrl+A 后按 X。反向执行需要专门的记录/回放支持，本次未配置或验证。

---

## 五、测试与验证

四张图片均来自成员实际终端，以下结论按可见内容说明。

### 5.1 最终环境

确认 Ubuntu 24.04.5、GCC 13.2.0、源码安装路径下的 QEMU 4.1.1、GDB 15.1 和 Make 4.3。

![最终实验环境与工具版本](./images/lab1_env_versions.png)

### 5.2 编译、格式与入口

```bash
make clean
make
ls -lh bin/kernel bin/ucore.img
file bin/kernel bin/ucore.img
riscv64-unknown-elf-readelf -h bin/kernel
```

截图显示 8 个源文件编译、链接、objcopy 完成。kernel 为静态链接、带调试信息的 RISC-V ELF64，入口 0x80200000；ucore.img 识别为 data。文件长度近似为 43K、13K。

![编译、产物格式和 ELF 入口](./images/lab1_make.png)

### 5.3 QEMU 启动

执行 make qemu，结果如下：

```text
OpenSBI v0.4 (Jul 2 2019 11:53:53)
Platform Name          : QEMU Virt Machine
Firmware Base          : 0x80000000
Runtime SBI Version    : 0.1
(THU.CST) os is loading ...
```

实际终端还用 timeout 8s make qemu 验证过相同输出；其后 Terminated 是主动超时终止，不是启动失败。截图显示固件和内核输出，完整参数以 code/Makefile 核对。

![QEMU 4.1.1 固件和内核输出](./images/lab1_make_qemu.png)

### 5.4 GDB 入口与栈

截图覆盖连接 PC、内核入口、初始 sp、栈边界、两次 si 和相等检查。结果与第四节一致，证明内核切换到自己的 8 KiB 栈。

![GDB 内核入口和栈初始化](./images/lab1_gdb_kernel.png)

### 5.5 make grade 与验证范围

Makefile 的 grade 目标执行 sh tools/grade.sh，但提供的实验包和当前 code/tools 均缺少该脚本。本报告没有 make grade 通过结果或截图，需向助教确认是否补发脚本或接受人工验证。

现有证据覆盖环境、编译、格式和入口、启动输出、栈初始化；无限循环有实际终端记录。BSS 清零和 SBI 调用链以源码分析为依据，没有单独的 BSS 内存检查或 ecall 单步截图，不声称完成这些独立动态测试。

### 5.6 提交结构

交付到小组仓库 lab1 分支：

```text
code/
  Makefile
  kern/
  libs/
  tools/
report/
  report.md
  prompt.md
  images/
    lab1_env_versions.png
    lab1_make.png
    lab1_make_qemu.png
    lab1_gdb_kernel.png
```

code 保留最小内核源码；qemu/debug 使用 loader 地址 0x80200000。本次没有新增内核功能。

---

## 六、实验总结与收获

### 对操作系统的理解

| 实验知识点 | 对应 OS 原理、关系与差异 |
|------------|-------------------------|
| Makefile 与交叉编译 | 构建依赖和目标架构；make 按依赖更新产物，不是简单顺序脚本 |
| ELF 与 bin | 可执行格式和加载机制；ELF 自描述，bin 依赖外部地址约定 |
| 链接脚本 | 内存布局；链接、装载、入口地址共同保证指令和数据引用正确 |
| 栈和 BSS 初始化 | 运行时建立；裸机必须自行准备 C 执行条件 |
| OpenSBI 和 ecall | 特权级与固件接口；S-mode 使用 M-mode 提供的服务 |
| 格式化与控制台封装 | 分层抽象；格式解析与设备输出分离 |
| GDB 单步 | 机器执行模型；伪指令可展开，源码行不等同机器指令 |

本实验没有对应 OS 原理中的进程调度、用户态隔离、页表管理、文件系统、完整系统调用、同步互斥和中断处理。页对齐为后续分页提供布局条件，并不意味着已经实现虚拟内存。

### AI 协作开发的经验

AI 能帮助解释 Makefile、链接脚本、调用链并设计调试步骤，但版本要求、实际源码和截图必须核对。QEMU 8.2.2 临时可运行不等于满足指定版本；最终完成 QEMU 4.1.1 源码构建和重新验证。

复核中修正了 BSS 转 bin 一定实体化、QEMU loader 不支持 ELF、S-mode 永远不能访问 UART 等概括，也修正了入口 section 与实际源码不一致的描述。分析结论应以源码和证据为准，不能只依赖 AI 表述。

共享分支需要先获取远程改动，再整合各成员内容和解决冲突；本次正常推送，不覆盖组员提交。提示词应包含文件、上下文和验收标准，并明确未完成的 grade 项，方便复现和答辩。
