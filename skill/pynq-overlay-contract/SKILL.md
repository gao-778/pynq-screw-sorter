---
name: pynq-overlay-contract
description: "检查或设计 PYNQ Overlay 的加载、BIT/HWH 配对、MMIO 元数据与接口契约。适用于自定义 FPGA IP 的驱动接入和硬件版本不匹配排查。"
---

# PYNQ Overlay 接口契约

以接口契约管理 Overlay，业务代码不保存散落的板卡常量。

## 契约与离线检查

收集器件/板卡、位流与硬件描述文件、地址位宽、各寄存器区域、IP 版本/能力以及时钟要求。BIT/HWH 从同次导出取得并保持同名；文件名相同本身不能证明配对。使用发布清单哈希建立来源关系。

需要离线检查 HWH 地址窗口与可选文件哈希时，使用 [scripts/check_contract.py](scripts/check_contract.py)。输入结构及示例见 [assets/contract.example.json](assets/contract.example.json)。示例地址仅用于展示格式，必须由目标工程导出信息替换。

```bash
python scripts/check_contract.py --hwh design.hwh --contract contract.json --report contract_report.json
```

若契约包含 bit_sha256，同时传入 `--bit design.bit`。工具只读取文件，不下载位流，也不证明运行时寄存器行为。

## 运行时流程

1. 核对加载操作作用的板卡和会话，避免另一个进程或会话仍持有运行中的主设备和缓冲区。
2. 由 PYNQ Overlay 加载成对产物，检查元数据对应的时钟与地址映射。
3. 同时考虑 `ip_dict` 与 `mem_dict`，不能因为 BRAM 寄存器窗口被归为 memory 就判定缺失。多层地址空间和多 master 视图必须明确适用的主机视角。
4. 自定义 IP 若提供 ABI、标识或能力寄存器，按契约读取；没有这些寄存器时使用该 IP 的实际兼容性依据，不能凭空读取约定地址。
5. 使用 `register_map` 或受契约约束的 MMIO，区分只读、写一清零、读有副作用和命令寄存器；避免探测性写入启动控制。
6. 匹配后才分配并绑定业务缓冲区、配置 IP 和启动服务。失败报告包含期望值、实际值、阶段和可恢复条件。

## 输出与边界

输出版本化契约、离线检查结果、运行时兼容性结果和驱动接入说明。更换板卡时修改契约及必要的时钟/地址适配，通用检查代码保持不变。

HWH 地址字段不足、地址转换、多地址空间或其他硬件描述格式需要独立适配；不得将离线地址覆盖检查扩大为器件兼容、模型正确或硬件行为正确的结论。

经验来源：元数据分类差异、位流/描述文件混用，以及同架构不同容量或软件 ABI 的不匹配。
