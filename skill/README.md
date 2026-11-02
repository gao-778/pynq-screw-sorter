# FPGA / PYNQ Skills

| Skill | 适用场景 | 使用方式 |
|---|---|---|
| fpga-system-partition | 数据流、软硬件划分与资源预算 | 提供算法、器件、接口及实时期限 |
| vision-motion-gating | 视觉与动作共享场景 | 提供状态机、帧有效性与恢复条件 |
| servo-bus-diagnostics | 半双工设备协议与事务服务 | 提供协议、接线和事务字段 |
| fpga-evidence-report | 参考比对、资源时序与可复现交付 | 提供基线、工具输出和测量边界 |
| baremetal-to-pynq | C 业务核心与平台适配 | 提供原入口、内存所有权与设备契约 |
| pynq-overlay-contract | BIT/HWH、地址窗口及接口核验 | 使用脚本和实际工程 contract.json |
| pynq-dma-lifecycle | 连续内存、缓存与停止排空 | 提供 IP 类型、地址能力及停止协议 |

各目录的 SKILL.md 给出使用流程、适用范围和边界。板卡地址、类别与运动坐标由目标工程配置，不作为通用默认值。可将完整子目录安装到技能工具的 skills 路径中。

本项目的实际 Overlay 契约位于 ../board/overlay_contract.json：

```bash
python skill/pynq-overlay-contract/scripts/check_contract.py --hwh board/hardware/screwsort.hwh --bit board/hardware/screwsort.bit --contract board/overlay_contract.json
```

脚本核验元数据与文件哈希，不代表板级性能测量。一般流程可以复用于其他题目；更换板卡时需要更新接口、地址、缓存和时钟条件。
