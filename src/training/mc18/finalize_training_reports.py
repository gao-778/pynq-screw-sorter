"""Project source and interface utilities."""
from settings import REPO_ROOT,TRAIN_OUTPUT,DATASET_INPUT
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parent
MODEL=REPO_ROOT/'data/model'
OUT=TRAIN_OUTPUT
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf8')
numeric=['model.bin','quantized_model.npz','best_qat.pt','weights.hex','biases.hex','shifts.hex','shape_model.h']
before={n:sha(MODEL/n) for n in numeric}
report=json.loads((MODEL/'test_report.json').read_text())
report['old_test_disclosure']='Legacy screw test partitions were evaluated during previous development. Their complete non-exposure to every historical pretraining/architecture choice is not established; treat old15 scores as internal regression, not a fresh independent generalization estimate. Nut test scenes were not used for this training/selection, but thumbnail quality audit preceded splitting.'
write(MODEL/'test_report.json',report);write(OUT/'final_test_report.json',report)
manifest=json.loads((MODEL/'model_manifest.json').read_text());manifest['test_status']='COMPLETED_AFTER_FREEZE; screened ROI classification, historical old15 internal regression'
manifest['test_report_sha256']=sha(MODEL/'test_report.json');manifest['test_coverage_report_sha256']=sha(MODEL/'test_coverage_report.json')
mapping=json.loads((ROOT/'label_mapping_status.json').read_text(encoding='utf8'))
manifest['label_mapping_status']=('USER_CONFIRMED: historical B=new L, M=M, S=S are the same three physical sizes; metric thread specifications remain unspecified' if mapping['status']=='USER_CONFIRMED' else 'ROOT_REVIEWED_ASSUMPTION: historical B=new L; image/size match, not user-confirmed metric thread size')
manifest['packed_parameter_bytes']=255510+402*4+3*4
write(MODEL/'model_manifest.json',manifest)
train=json.loads((MODEL/'training_report.json').read_text());train['selection_policy']='Best original-guard-passing joint_qat epoch among exactly three completed epochs; head is a comparison only, not a final candidate; test never used.'
train['capacity_limitation']='Expanded initialization followed by conservative joint quantization fine-tuning; no demonstrated old15 accuracy improvement. Do not equate 255912 parameters with that many independently newly learned features.'
write(MODEL/'training_report.json',train)
hash_names=numeric+['model_manifest.json','training_report.json','test_report.json','test_coverage_report.json','export_verification.json','reference.py','weight_change_report.json','classes.json','README.md']
write(MODEL/'artifact_hashes.json',{n:sha(MODEL/n) for n in hash_names})
assert before=={n:sha(MODEL/n) for n in numeric}
lines=['# 最终训练与验证结果','',
 '模型已冻结，三轮联合量化微调中选择第1轮。第2轮未通过原有旧类保护门槛，第3轮通过但验证综合分数较低。测试在冻结后仅评估一次，没有按测试结果重新选模型。','',
 '| 测试内容 | 有效 ROI 数 | 十八类整体 | 十五类螺丝 | 三类螺母 |','|---|---:|---:|---:|---:|']
names={'clean':'原始筛选ROI','pose':'相邻角度/小位移扰动','photo':'光强/gamma/阴影/噪声扰动'}
for f in ['clean','pose','photo']:
    rr=report['results'][f]
    lines.append(f"| {names[f]} | {rr['overall']['count']} | {rr['overall']['accuracy']:.3%} | {rr['screws']['accuracy']:.3%} | {rr['nuts']['accuracy']:.3%} |")
lines+=['','| 来源域 | 原始 ROI | 姿态扰动 | 光度扰动 |','|---|---:|---:|---:|']
for d in sorted(report['results']['clean']['domains']):
    lines.append('| '+d+' | '+' | '.join(f"{report['results'][f]['domains'][d]['accuracy']:.3%}" for f in ['clean','pose','photo'])+' |')
lines+=['',
 '原始照片2404张，其中2张因手遮挡隔离；train/val/test分别1673/365/364张。原始筛选有效实例分别15952/3473/3484个。训练增强后79637条ROI，验证31175条ROI；这些条目不是同数量的照片或独立实物。',
 '',
 '255912是可训练参数容量。相对破对称初始化，最终INT8卷积权重实际更新3个（第三层），三个卷积层偏置分别更新25/63/197个；初始化预置的6144个扰动不计作学习。新增螺母头充分量化训练，卷积部分是保守扩宽微调；没有证据表明旧十五类精度明显提高。',
 '',
 '162个按类别/来源/增强族覆盖的验证样本逐层通过独立NumPy int64对比；NPZ、HEX、C头与FNET BIN参数及CRC一致。真实5颗NUT_M验证帧由整数CNN输出class16，未注入类别。FPGA端完整链路仿真、时序和启动打包报告见Vivado工程，真实上板效果另行验证。',
 '',
 '旧螺丝测试分组在历史开发中已使用，不能证明对所有历史预训练/架构选择从未曝光，应作为内部回归。新螺母测试图未参与本轮训练/选参，但分组前质量审核看过缩略图。数据来自同一类固定拍摄平台，结果不能作为陌生相机/任意光照保证。',
 '',
 '以上准确率分母为筛选后的ROI。检测候选、拒绝、光度变换后重检测匹配的分母见test_coverage_report.json；这不是人工独立计数的全场检出率，也不是机械臂夹取成功率。',
 '',
 ('用户已确认旧B对应新L，M、S也分别为同种实物尺寸；具体公制螺纹规格仍未提供。' if mapping['status']=='USER_CONFIRMED' else '旧B和新L的合并是基于视觉/尺寸证据的已审查假设，尚未由用户确认。'),
 '',
 f"冻结BIN SHA256：`{before['model.bin']}`。",f"冻结NPZ SHA256：`{before['quantized_model.npz']}`。",'']
(TRAIN_OUTPUT/'training_results.md').write_text('\n'.join(lines),encoding='utf8')
print(json.dumps({f:{d:r['accuracy'] for d,r in report['results'][f]['domains'].items()} for f in report['results']},ensure_ascii=True))
