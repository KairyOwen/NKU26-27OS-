# tools/gdb —— 双 GDB 联调脚本（lab2，QEMU 4.1.1）

把「内核视角」和「QEMU 模拟器视角」对同一次内存访问的翻译过程同时留下证据：

- **客体 gdb**（`riscv64-unknown-elf-gdb`）经 QEMU gdbstub 调试 ucore 内核：
  观察 `kern_entry` / `kern_init` / `memset` / `pmm_init` 处的 pc、satp、页表项和参数寄存器。
- **宿主 gdb**（`/usr/bin/gdb`）经 ptrace attach 到 **QEMU 进程本身**，调试模拟器内部：
  在 `accel/tcg/cputlb.c` 的 `tlb_fill` / `tlb_set_page_with_attrs`（tn 填充）和
  `target/riscv/cpu_helper.c` 的 `riscv_cpu_tlb_fill` / `get_physical_address`
  （Bare 分支、PTE 读取、叶项 physical 计算）下断点，记录 VA→PA 与 TLB 填充参数。

## 文件

| 文件 | 作用 |
| --- | --- |
| `run-dual-reset.sh` | **首选**双 GDB 流程：从复位向量开始，宿主 gdb 观察 OpenSBI→Bare 首取指→Sv39 |
| `run-dual-detach.sh` | 备选双 GDB 流程：客体先把内核驱动到 `kern_entry`/satp 打开，再交接给宿主 gdb |
| `run-guest-gdb.sh` | 只用客体 gdb 驱动内核，同时用 QEMU `-d mmu` 记录 `mmu.log` |
| `run-host-gdb.sh` | 只用宿主 gdb attach QEMU，记录正常启动过程中的页表遍历 |
| `guest-reset.gdb` / `guest-detach.gdb` | 上面两个双 GDB 流程的客体侧脚本 |
| `guest.gdb` | 单客体脚本：`kern_entry` 起逐步打开 satp，再观察 `kern_init`、`boot_page_table_sv39[511]`、`memset` 参数 |
| `host.gdb` | 宿主侧脚本：QEMU 4.1.1 内部断点与日志格式 |

## 端口为什么是 43210

QEMU gdbstub 默认端口 1234，但本机 **1234 被 Windows 端微信占用**。因此全部脚本统一
`-gdb tcp::43210`（脚本里）与 `target remote localhost:43210`（gdb 里）。
若 43210 也被占用，先 `ss -ltn | grep 43210` 检查。

## 双 GDB 时序

### A. 复位流程（`run-dual-reset.sh`，本次实测采用）

1. QEMU 4.1.1 以 `-S` 停在复位向量等 gdbstub；
2. 客体 gdb 连上 gdbstub，停在复位处（pc=0x1000），写 `/tmp/guest_ready`，然后
   `shell while [ ! -f /tmp/host_ready ]; do sleep 0.2; done` 等宿主就绪；
3. 宿主 gdb `-p $QPID attach` 到 QEMU 进程，安装 QEMU 内部断点，`shell touch /tmp/host_ready`，
   再 `continue` 让被 ptrace 停住的 QEMU 进程继续运行；
4. 客体 gdb 看到 `/tmp/host_ready` 后 `detach`；QEMU gdbstub 在最后一个 gdb 断开时执行
   `gdb_continue()`（`gdbstub.c` 的 `handle_detach`），VM 开始从复位向量执行；
5. 宿主 gdb 从 OpenSBI 开始观察：Bare 模式首条 S 模式取指 → satp 打开后的 Sv39 取指 →
   memset 的第一次数据 store 的页表遍历。

### B. detach 流程（`run-dual-detach.sh`，脚本保留，本次未运行）

1. 客体 gdb 先驱动内核到 `kern_entry`（pc=0x80200000，satp=0），`stepi` 直到写出 satp，
   再用 `break kern_init` 预置 Sv39 虚拟地址断点；
2. 客体写 `/tmp/guest_ready` 并等 `/tmp/host_ready`；
3. 宿主 gdb attach、安装同样的 QEMU 断点、touch `/tmp/host_ready`；
4. 客体 detach，QEMU 恢复运行；宿主 gdb 观察 `kern_init` 取指与 memset store 的翻译。

两种流程里宿主看到的事件相同；复位流程额外能看到 OpenSBI 与 Bare 模式第一条取指，
所以作为首选。

## 运行命令

```sh
# 1) 构建（默认 PMM=best_fit，与证据一致）
cd <仓库根>/code
make clean && make -j4

# 2) 首选双 GDB（日志默认写到 code/../report/logs/gdb-b/）
sh tools/gdb/run-dual-reset.sh

# 3) 补 mmu.log / serial.log / guest-gdb.log（同一构建、单 QEMU、串行执行）
sh tools/gdb/run-guest-gdb.sh

# 4) 可选：QEMU 版本对照（用 4.1.1 跑课程评分；PATH 默认 7.0.0 会得到 0/20，
#    对照日志见 report/logs/repro-b/grade-with-default-qemu-7.0.0.log）
QEMU=$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64 bash tools/validate.sh grade
```

构建命令：默认 `make clean && make`（PMM=best_fit，本双 GDB 证据所用构建；本次实测
用等价的 `make -j4`）；Buddy 复现用 `make clean && make PMM=buddy`。
`report/logs/repro-b/build-best-fit.log` 与 `build-buddy.log` 只记录编译行，对应的
命令行以本节为准。

前提：

- `$HOME/qemu-4.1.1/riscv64-softmmu/qemu-system-riscv64` 必须是 **4.1.1 调试版**
  （脚本默认值，可用环境变量 `QEMU=...` 覆盖）。PATH 上的
  `/opt/qemu/bin/qemu-system-riscv64` 是 **7.0.0**，自带
  `opensbi-riscv64-generic-fw_dynamic.bin`（2022-04 构建），与 4.1.1 的 OpenSBI v0.4
  固件（`pc-bios/opensbi-riscv64-virt-fw_jump.bin`）不同；本项目 `tools/validate.sh`
  第 20–24 行硬性检查只接受 `QEMU emulator version 4.1.1`。本次双 GDB 与启动观测
  证据只使用 4.1.1；7.0.0 另做过一次 `make grade` 对照（0/20，见
  `report/logs/repro-b/grade-with-default-qemu-7.0.0.log`），不作为本实验运行环境。
- 宿主 gdb 需要 ptrace 权限：`kernel.yama.ptrace_scope=0`。
  **本机 WSL2 每次实例重启都会把它重置为 1**，此时 attach 会报
  `Could not attach to process ... ptrace_scope`。必须在**同一个 WSL 会话**里先执行
  `sudo sysctl -w kernel.yama.ptrace_scope=0` 再跑脚本（本次实测前两次运行即分别因
  ptrace_scope=1 导致宿主 attach 失败、以及以 root 用非登录 shell 切换用户导致
  `riscv64-unknown-elf-gdb` 不在 PATH 而失败；第三次设 0 + 登录 shell 后成功，
  见 `report/logs/gdb-b/` 的日志）。
- 同一时间只跑一个 QEMU 实例；跑完确认没有残留 `qemu-system-riscv64` / `gdb` 进程。

本次证据的实际环境（完整命令输出见 `report/logs/gdb-b/environment.log`）：
Ubuntu 26.04 LTS（WSL2，6.18.33.2-microsoft-standard-WSL2），用户 hanmiao33；
`riscv64-unknown-elf-gcc 16.1.0` / binutils 2.47，GNU Make 4.4.1，Python 3.14.4；
QEMU 4.1.1 调试版；宿主 gdb 17.1（`/usr/bin/gdb`）；
客体 gdb 17.2（`riscv64-unknown-elf-gdb`）。

## 脚本按当前构建改了什么

当前 lab2 默认 `best_fit` 构建（HEAD 763a19d）实测布局：

| 符号 | VA | 说明 |
| --- | --- | --- |
| `kern_entry` | `0xffffffffc0200000` | ELF Entry point；PA 0x80200000 |
| `kern_init` | `0xffffffffc02000d6` | 内核 banner 里打印的 “entry” 就是它 |
| `etext` | `0xffffffffc02016be` | |
| `boot_page_table_sv39` | `0xffffffffc0205000` | PA 0x80205000 → satp 0x8000000000080205 |
| `boot_page_table_sv39[511]` | `0xffffffffc0205ff8` | PA 0x80205ff8，值 0x200000cf |
| `edata` | `0xffffffffc0206018` | 第一条 memset store 的 VA → PA 0x80206018 |
| `end` | `0xffffffffc0206078` | |

相对旧备份脚本的地址改动：

- `guest.gdb`：PTE[511] 的 VA `0xffffffffc0206ff8` → `0xffffffffc0205ff8`，注释同步；
- `host.gdb`：数据 store 相关 `0xffffffffc0207018` → `0xffffffffc0206018`，
  `0xffffffffc0207000` → `0xffffffffc0206000`，注释同步；
- 全部 `run-*.sh`：`LOG_DIR` 默认改为 `$CODE_DIR/../report/logs/gdb-b`，端口保持 43210。

`host.gdb` 的断点行号已对 `~/qemu-4.1.1` 源码核对（QEMU 4.1.1）：

- `target/riscv/cpu_helper.c`：`get_physical_address` 定义 155 行、Bare/MBARE 分支
  `*physical = addr` 在 197 行、`pte = ldq_phys(...)` 252 行、叶项 physical 计算 334 行
  （gdb 实际落在 336→337 行）；`riscv_cpu_tlb_fill` 定义 435 行（gdb 落 438 行）。
- `accel/tcg/cputlb.c`：`tlb_set_page_with_attrs` 697 行、tn 填充 800–835 行
  （断点落 836 行）、`tlb_fill` 868 行（gdb 落 871 行）、`get_page_addr_code` 1032 行。

## 预期观察（本次实测值，详见 `report/logs/gdb-b/`）

客体（`guest-gdb.log`）：

- `kern_entry`：pc=`0x80200000`，satp=`0`（Bare）；
- 15 次 `stepi` 后 satp=`0x8000000000080205`，pc=`0x80200038`；
- `kern_init`：pc=`0xffffffffc02000d6`，satp=`0x8000000000080205`；
- `boot_page_table_sv39[511]`（VA 0xffffffffc0205ff8）=`0x200000cf`，satp PPN=`0x80205`；
- `memset` 入口：`a0(s)`=`0xffffffffc0206018`，`a1(c)`=0，`a2(n)`=`0x60`（96）。

宿主（`host-gdb.log`）：

- Bare 取指：`tlb_fill(addr=0x80200000, size=0, MMU_INST_FETCH, mmu_idx=1)` →
  `get_page_addr_code` → `riscv_cpu_tlb_fill(0x80200000)` → Bare 分支 `*physical=0x80200000`；
- Sv39 取指：`tlb_fill(0xffffffffc02000d6)` → `riscv_cpu_tlb_fill` →
  `get_physical_address(0xffffffffc02000d6, MMU_INST_FETCH)`（satp=0x8000000000080205，priv=1）→
  `i=0 idx=511 pte_addr=0x80205ff8 pte=0x200000cf（PFN 0x80000）ptshift=18` →
  叶项 `physical=0x80200000` → `TLB FILL vaddr_page=0xffffffffc0200000 paddr=0x80200000 index=0`；
- Sv39 数据 store：`tlb_fill(0xffffffffc0206018, size=1, MMU_DATA_STORE, mmu_idx=1)` →
  `get_physical_address`（同一 PTE）→ `physical=0x80206000` →
  `TLB FILL vaddr_page=0xffffffffc0206000 paddr=0x80206000 index=6`；
- `tlb_set_page` 调用参数：`vaddr_page=0xffffffffc0200000`、`paddr=0x80200000`
  （cputlb.c:836 处实测），`mmu_idx=1`（tlb_fill 处实测），
  `size=TARGET_PAGE_SIZE=0x1000`、`prot` 由 `cpu_helper.c:472-473` 的调用点与
  `mmu.log` 的 `prot 7`（PAGE_READ|PAGE_WRITE|PAGE_EXEC）确定（源码行号基于本机
  QEMU 4.1.1 源码 `~/qemu-4.1.1`，未随仓库提供）。

`mmu.log`（QEMU `-d mmu`，52 KB）：

```
riscv_cpu_tlb_fill ad ffffffffc02000d6 rw 2 mmu_idx 1
riscv_cpu_tlb_fill address=ffffffffc02000d6 ret 0 physical 0000000080200000 prot 7
riscv_cpu_tlb_fill ad ffffffffc0206018 rw 1 mmu_idx 1
riscv_cpu_tlb_fill address=ffffffffc0206018 ret 0 physical 0000000080206000 prot 7
```

串口日志：内核 banner 的 entry/etext/edata/end 与上表一致，
`best_fit_pmm_manager`，`satp virtual address: 0xffffffffc0205000` /
`satp physical address: 0x80205000`。

## 日志位置

`report/logs/gdb-b/`（本次实测产物）：

- `run-dual-reset.sh`：`guest-reset.log`、`host-gdb.log`、`host-stdout.log`、
  `serial-reset.log`、`qemu-reset.log`；
- `run-guest-gdb.sh`：`guest-gdb.log`、`mmu.log`、`serial.log`、`qemu.log`；
- `environment.log`：工具链与环境实测记录（`uname -a`、发行版、gcc/binutils、
  宿主/客体 gdb、脚本所用 QEMU 4.1.1 与 PATH 上 7.0.0 的版本、repo HEAD、资源与
  ptrace_scope 当前值）。

说明：

- 本目录日志是 2026-10-22 00:43–00:44（宿主机时间）这一次串行实测的产物，
  **定稿后未再重跑覆盖**；`environment.log` 于 00:48 追加，01:06 又追加一段
  `command -v`/`ls -l` 路径核对（段内自带时间戳，未改动前 42 行）。

- `serial.log` 在客体 gdb `detach` 后 QEMU 立即被脚本终止，最后一行是截断的
  （真实行为，非人为裁剪）；`serial-reset.log` 是完整启动输出。
- `mmu.log` 52 KB，全量保留（未超过 5 MB 上限）。
- `host-gdb.log` 中 QEMU 调试符号路径为 `/home/hanmiao33/qemu-4.1.1/...`，
  可佐证使用的是 4.1.1 调试版而不是 PATH 上的 7.0.0。

## 已知差异 / 注意事项

- 任务背景里 “entry=0xffffffffc02000d6” 指的是**内核 banner 打印的 entry**（即 `kern_init`）；
  ELF 的 Entry point 实际是 `0xffffffffc0200000`（`kern_entry`）。
- 本机 `which qemu-system-riscv64` 指向 `/opt/qemu/bin`（7.0.0），脚本默认用
  `$HOME/qemu-4.1.1` 的 4.1.1，运行脚本时不要设置 `QEMU` 指向 7.0.0。
- 前两次失败（ptrace_scope=1 导致 attach 失败；root 非登录 shell 导致
  `riscv64-unknown-elf-gdb` 不在 PATH）的运行日志**未单独归档**：它们已被随后成功
  运行的 `host-gdb.log` / `host-stdout.log` 覆盖（`set logging overwrite on` 与 shell
  重定向截断），只在当时的终端输出中可见；本 README 只记录现象与报错文本，不声称
  日志文件里保留了失败记录。
- 宿主 gdb 17.1 对 `set logging on` 有弃用告警（仍可用；`host-stdout.log` 中会看到），
  不影响 `host-gdb.log` 的内容。
