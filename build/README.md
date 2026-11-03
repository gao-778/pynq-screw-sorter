# 构建与发布

统一入口为 `python build/build.py <target>`；[project.json](project.json) 定义共享源码、两个 PS 编译目标及硬件接口。先确认 [复现范围](../report/reproducibility.md)：公开源码不含所有构建输入，完整主机回归还需要匹配运动学实现和同版 HWH 元数据；逐步说明见 [完整复现指南](../report/quickstart.md)。

| target | 作用 | 输出/限制 |
|---|---|---|
| `linux` | 在 PYNQ/ARM Linux 编译 C 共享库 | `build/output/linux/libscrewlab.so`；Windows `--host` 是主机测试库，不可装到板上 |
| `baremetal` | 使用 Vitis/BSP 编译 standalone ELF | `build/output/baremetal/screwsort.elf` |
| `boot` | 用匹配 FSBL、BIT 和 ELF 打包 | `board/baremetal/boot.bin`；只用于裸机启动 |
| `hardware` | 从 RTL/XDC/BD Tcl 重建和导出共享 PL | 同次 XSA 的 BIT/HWH；`--prepare-only` 仅生成工程 |
| `verify` | 检查交付文件对应关系 | source 包可列出尚缺的本地依赖；不访问硬件 |

## 依赖与工作目录

[dependencies.json](dependencies.json) 注册本地输入、哈希、旧发行目录路径和公开排除规则。导入与实际复制分离：全部源输入核验通过后才写入工作副本。

```bash
python build/import_dependencies.py --release /path/to/full/screwsort
```

`--release` 可指向完整统一包的 `screwsort` 目录，或清单兼容的旧发行目录。导入脚本不导入运行位流；选择从源码构建硬件，或使用有权取得的完整统一包本身进行运行。

`output/` 是当前构建输出，`local/` 是本地依赖，`reports/` 是既有实现与编译证据。保留历史证据，新的检查结果使用独立输出目录，不以覆盖旧日志冒充新测量。

## 检查与归档

```bash
python build/verify.py
python -m unittest discover -s sim/tests -p test_release_packaging.py -v
```

仓库检查允许 Git 元数据与根许可证等维护文件；它们不改变七个业务目录。Git 元数据、缓存和当前运行输出不属于发布文件。修改可发布文件后应检查修改内容，再运行：

```bash
python build/package.py --refresh
python build/verify.py
python build/package.py --public --output /path/outside/project/screwsort_source.zip
```

`--refresh` 只更新文件清单，不验证算法正确性、不使缺件可用，也不授予第三方再分发许可。公开包通过 `--public` 排除 [本地依赖](dependencies.json)；完整本地包不加该选项。输出路径必须在项目外且尚不存在。

参赛平台若仍要求 RAR，应将核验后的交付目录用 RAR 工具重新压缩，不能只改 ZIP 后缀。完整包是否能提交需按其中第三方材料的许可处理。公开源码、参赛包与报告应记录同一个源码提交和对应产物哈希。
