# FastCDC 基准测试工具使用说明

## 📋 概述

本目录包含两个基准测试脚本:

1. **benchmark_fastcdc.sh** - 基础版本（单次测试）
2. **benchmark_fastcdc_advanced.sh** - 高级版本（多次重复测试 + CSV输出）⭐ 推荐

## 🚀 快速开始

### 运行高级版测试（推荐）

```bash
cd /home/wfy/DADI_OverlayBD_demo/overlaybd
./benchmark_fastcdc_advanced.sh
```

### 运行基础版测试

```bash
cd /home/wfy/DADI_OverlayBD_demo/overlaybd
./benchmark_fastcdc.sh
```

## ⚙️ 高级版配置

在 `benchmark_fastcdc_advanced.sh` 中可以修改以下参数:

```bash
# 重复测试次数（默认5次）
# 增加次数可以提高结果可靠性，但会延长测试时间
REPEAT_COUNT=5

# 工作目录（测试数据和结果存放位置）
WORK_DIR=/home/wfy/DADI_OverlayBD_demo/experiments/fastcdc_benchmark
```

## 📊 输出文件说明

测试完成后会在 `$WORK_DIR` 目录生成以下文件:

### 1. benchmark_results.csv
**详细数据文件** - 包含每次测试的原始数据

| 列名 | 说明 | 示例 |
|------|------|------|
| Timestamp | 测试时间戳 | 2025-11-09 14:37:21 |
| RunID | 运行编号 (1-5) | 3 |
| TestName | 测试名称 | mixed_10m |
| DataType | 数据类型 | mixed |
| FileSizeKB | 文件大小(KB) | 10240 |
| OriginalBytes | 原始字节数 | 10485760 |
| Method | 压缩方法 | FastCDC |
| CompressedBytes | 压缩后字节数 | 216064 |
| CompressionRatio | 压缩率(%) | 2.06 |
| CompressTime_ms | 压缩时间(毫秒) | 104 |
| DecompressTime_ms | 解压时间(毫秒) | 72 |
| MD5Verified | MD5校验结果 | true |

### 2. benchmark_summary.csv
**统计汇总文件** - 包含平均值、标准差和性能对比

| 列名 | 说明 |
|------|------|
| AvgCompressedBytes | 平均压缩后大小 |
| StdCompressedBytes | 压缩后大小的标准差 |
| AvgCompressionRatio | 平均压缩率 |
| StdCompressionRatio | 压缩率的标准差 |
| AvgCompressTime_ms | 平均压缩时间 |
| StdCompressTime_ms | 压缩时间的标准差 |
| AvgDecompressTime_ms | 平均解压时间 |
| StdDecompressTime_ms | 解压时间的标准差 |
| SpaceSaving% | 空间节省百分比 (FastCDC vs 固定分块) |
| SpeedupCompress | 压缩速度倍数 |
| SpeedupDecompress | 解压速度倍数 |

### 3. benchmark_results.txt
**人类可读的文本报告**

## 📈 数据分析示例

### 使用Excel/LibreOffice

1. 打开 `benchmark_summary.csv`
2. 创建数据透视表
3. 绘制图表对比:
   - 压缩率对比
   - 速度对比
   - 空间节省

### 使用Python/pandas

```python
import pandas as pd
import matplotlib.pyplot as plt

# 读取详细数据
df = pd.read_csv('benchmark_results.csv')

# 按测试名称和方法分组
grouped = df.groupby(['TestName', 'Method'])

# 绘制解压时间对比
pivot = df.pivot_table(
    values='DecompressTime_ms', 
    index='TestName', 
    columns='Method', 
    aggfunc='mean'
)
pivot.plot(kind='bar', title='解压时间对比')
plt.ylabel('时间 (ms)')
plt.show()

# 读取汇总数据
summary = pd.read_csv('benchmark_summary.csv')
fastcdc = summary[summary['Method'] == 'FastCDC']

# 显示空间节省最大的测试
print(fastcdc.nlargest(5, 'SpaceSaving%')[
    ['TestName', 'SpaceSaving%', 'SpeedupDecompress']
])
```

## 🎯 测试用例说明

### 1. Random (随机数据)
- **目的**: 测试最坏情况（不可压缩数据）
- **预期**: 压缩率接近100%
- **意义**: 验证FastCDC不会比固定分块更差

### 2. Pattern (重复模式)
- **目的**: 测试理想情况（高度可压缩）
- **预期**: 两种方法都有很高的压缩率
- **意义**: 验证基础压缩能力

### 3. Mixed (混合数据) ⭐ 关键测试
- **目的**: 模拟真实容器镜像场景
- **数据结构**: 交替的重复块和随机块
- **预期**: FastCDC表现明显优于固定分块
- **意义**: 
  - 固定分块可能会在块边界处切断重复模式
  - FastCDC能识别内容边界，保持重复块完整
  - 这是FastCDC最能体现优势的场景！

### 文件大小选择
- **100KB**: 小文件，测试基本功能
- **1MB**: 中等文件，常见场景
- **10MB**: 大文件，压力测试

## 🔍 结果解读

### 好的结果特征

1. **低标准差** (< 5%)
   - 表示测试结果稳定可靠
   - 如果标准差过大，可能需要增加 `REPEAT_COUNT`

2. **混合数据的高空间节省** (> 50%)
   - 证明FastCDC在真实场景中有实际价值
   - 空间节省率越高，说明内容感知分块越有效

3. **解压速度提升** (> 5x)
   - 更少的块意味着更少的开销
   - 解压速度是实际部署中的关键指标

### 示例好结果

```
TestName             Method     平均压缩率    空间节省    解压加速
-------------------- ---------- ------------ ------------ ------------
mixed_10m            FastCDC    2.06%±0.05%  92.27%      22.40x
```

这表示:
- 压缩率稳定 (标准差0.05%)
- 节省92%的空间（从2.7M降到211K）
- 解压速度快22倍

## ⚠️ 注意事项

1. **测试环境**: 确保测试期间系统负载稳定
2. **磁盘空间**: 确保有足够空间存储测试数据（约10MB × 3种类型 × 3种大小 × 5次重复 × 2种方法）
3. **权限**: 需要读写 `/tmp` 或指定工作目录的权限
4. **Python依赖**: 需要Python 3（用于生成测试数据和统计分析）

## 🛠️ 故障排除

### 问题: "MD5校验失败"
**原因**: 压缩/解压数据损坏
**解决**: 检查 `overlaybd-zfile` 是否正确编译

### 问题: "标准差过大"
**原因**: 系统负载不稳定或测试次数不足
**解决**: 
```bash
# 增加重复次数
REPEAT_COUNT=10
```

### 问题: "测试时间过长"
**原因**: 重复次数过多或测试文件过大
**解决**: 减少测试用例或减小文件大小

## 📚 扩展测试

### 添加自定义测试

编辑脚本,在主程序部分添加:

```bash
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}测试 4: 自定义测试${NC}"
echo -e "${YELLOW}========================================${NC}"
run_test_suite "custom_5m" 5120 "mixed"
```

### 测试实际文件

```bash
# 复制实际文件到工作目录
cp /path/to/your/file "$WORK_DIR/real_file.dat"

# 手动测试
cd "$WORK_DIR"
$ZFILE real_file.dat real_file_fixed.zfile
$ZFILE --fastcdc real_file.dat real_file_fastcdc.zfile
```

## 📞 支持

如有问题,请检查:
1. `benchmark_results.txt` 中的错误信息
2. CSV文件是否正确生成
3. 标准差是否在合理范围内

---

**最后更新**: 2025-11-09  
**版本**: 2.0 (高级版)
