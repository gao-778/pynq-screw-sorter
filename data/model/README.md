# MC18 模型

类别顺序由 classes.json 定义。15 类螺丝与 NUT_L/NUT_M/NUT_S 共 18 类。输入 64×64 灰度，通道 1→32→96→256，255510 个权重、402 个偏置、3 个移位参数。

model.bin 为 FNET-v1：24 字节头加 uint32 参数容器；quantized_model.npz 与 weights.hex/biases.hex/shifts.hex 为同一参数的数组及十六进制表示；../../src/common/shape_model.h 是 C 嵌入表示。构建校验逐项核对这些表示的内容、CRC 和 SHA-256。

reference.py 提供整数参考计算；model_manifest.json 定义 ROI、几何量、量化与寄存器契约。训练使用 ../../src/training/README.md 中的入口。导出新模型后，检查 C 参数、类别顺序和 PL 结构一致再构建两种目标。
