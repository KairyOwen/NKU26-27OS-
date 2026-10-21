# Lab 2 运行说明

## 构建与启动

使用 riscv64-unknown-elf 工具链、源码编译的 QEMU 4.1.1、GNU Make。
本实验沿用课程 loader 参数，不采用为新版本 QEMU 调整过的 -kernel 参数。

```bash
make clean
make
make QEMU="$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64" qemu
```

内核完成检查后停留在无限循环，Ctrl+A 后按 X 可退出 QEMU。

默认管理器为 Best-Fit。Buddy 单独验证：

```bash
make clean
make PMM=buddy
make PMM=buddy QEMU="$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64" qemu
```

切换 PMM 参数必须 clean 后重编译，现有对象依赖规则不跟踪编译参数变化。
Buddy 的 alloc_pages(n) 实际占用向上取 2 的幂的块，free_pages(base,n)
必须传入原请求 n，整块释放，不支持部分释放。最高阶 15 与固定管理上界对应。
不支持并发调用，也不声称是生产级分配器。

## 课程评分

```bash
make QEMU="$HOME/opt/qemu-4.1.1/bin/qemu-system-riscv64" GDB=gdb-multiarch grade
```

需要 python3、bc。grade 使用原始注入和评分脚本，只检查其规定的
Page Init/Best-Fit 项目，不能代替 Buddy 或 GDB 分支任务验证。

## 分阶段记录

```bash
bash tools/validate.sh env
bash tools/validate.sh best-fit
bash tools/validate.sh grade
bash tools/validate.sh buddy
bash tools/validate.sh restore
```

脚本默认搜索当前用户下的安装/构建路径，也支持设置 QEMU=/actual/path。
运行限时 30 秒，日志写入 ../report/logs；通过标准是实际检查输出，而非单纯
超时退出。若验证脚本与交互终端不兼容，可直接运行上面的 make/QEMU 命令。

## GDB

恢复默认 Best-Fit 后启动暂停的客体：

```bash
make clean
make
make QEMU="$HOME/src/qemu-4.1.1-debug-build/riscv64-softmmu/qemu-system-riscv64" debug
```

源码调试需要 --enable-debug 的 QEMU 独立构建。宿主 GDB 附加到 QEMU 进程，
客体 gdb-multiarch 连接 localhost:1234。两者是不同调试目标；宿主暂停时，
客体调试协议可能等待。客体连接可用 make GDB=gdb-multiarch gdb。

## 原生辅助检查

tools/host-check/README.md 给出适配层和运行方法。该检查编译相同的算法
源文件，覆盖原有 Best-Fit 测试、Buddy 行为检查与混合操作；不验证
RISC-V 启动、DTB 或 page_init，不能替代客体实测。
