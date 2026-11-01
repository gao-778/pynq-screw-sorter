# MC18 部署模型

本目录对应 `BUILD_MC18_UI_MINT_ARM_BUS_FIX_20261101` 的部署参数。类别的内部顺序见 `classes.json`，不能直接按屏幕编号重排。

- `model.bin`：FNET-v1 文件；24 字节头，后接硬件加载用的 INT32 容器。
- `weights.hex`、`biases.hex`、`shifts.hex`：导出的整数参数。
- `quantized_model.npz`：主机参考计算使用的量化数组。
- `reference.py`：整数模型参考实现。
- `model_manifest.json`：输入、旋转 ROI、几何量与寄存器地址契约。
- `software/shape_model.h`：同一参数的 C 内嵌表示。

255,510 个权重＋402 个偏置＝255,912 个可训练参数，另外有 3 个量化移位值。输入是 64×64 单通道；不是任意 ONNX/YOLO 权重都可直接替换。

训练过程、最终产物关联和无法直接复现的外部依赖见 [训练说明](../training/README.md) 与 [模型文档](../docs/MODEL.md)。原始照片、教师训练资料和缓存未随源码发布；不把历史内部测试结果当成独立场景的现场准确率保证。
