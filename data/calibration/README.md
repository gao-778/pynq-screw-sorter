# 平台标定

坐标单位为毫米，原点为平台标记，显示方向为 +X 向右、+Y 向上。platform_calibration.h 与 ../../src/common/platform_calibration.h 对应同一标定。

安装 requirements.txt 后，将平台 40/80/120 mm 参考方框的灰度帧与角点种子提供给 calibrate_platform.py。生成的 calibration.json、platform_calibration.h 和 calibration_axes.png 用于核对变换。将完成验收的参数复制到共享 C 核心后，重新构建两种目标。

test_obb_coordinates.py 验证旋转框中心及轴向的坐标计算；verify_repetition.py 比较多帧标定结果。这里的参考测量属于示例装置，新装置需要独立标定。
