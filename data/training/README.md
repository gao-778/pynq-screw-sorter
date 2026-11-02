# 训练输入

本目录供照片、标注与准备数据使用。SCREWSORT_DATASET 可指向另一个数据根目录。

prepare_data.py 需要 inputs/fixed_split_manifest.json、output/dataset_trainval.npz，以及 src/training/mc18/nut_scan.json。测试数据使用 output/dataset_test.npz。螺母场景清单应包含 source、class_name、frame_rejected 及前处理程序读取的分组/目标字段。路径应指向实际图像；固定场景分组应在训练前完成。

若已有完整的 MC18 准备数据，可直接放入 SCREWSORT_TRAIN_OUTPUT 指定的 dataset_trainval.npz 与 dataset_test.npz，使用训练入口。文件至少包含 images64、geometry、labels、splits，以及训练脚本用于统计与评估的 family、lighting、ids 等字段。
