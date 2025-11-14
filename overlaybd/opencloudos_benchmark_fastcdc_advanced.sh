#!/bin/bash

# FastCDC vs 固定大小分块性能对比测试 - 高级版
# 支持多组重复测试和CSV输出

set -e

# ============ 配置参数 ============
ZFILE=/root/DADI_OverlayBD_demo/overlaybd/build/output/overlaybd-zfile
WORK_DIR=/root/DADI_OverlayBD_demo/experiments/fastcdc_benchmark
RESULT_FILE="$WORK_DIR/benchmark_results.txt"
CSV_FILE="$WORK_DIR/benchmark_results.csv"
CSV_SUMMARY="$WORK_DIR/benchmark_summary.csv"

# 重复测试次数（建议3-5次以获得稳定结果）
REPEAT_COUNT=5

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 创建工作目录
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 初始化CSV文件
init_csv() {
    # 详细数据CSV（每次测试的原始数据）
    echo "Timestamp,RunID,TestName,DataType,FileSizeKB,OriginalBytes,Method,CompressedBytes,CompressionRatio,CompressTime_ms,DecompressTime_ms,MD5Verified" > "$CSV_FILE"
    
    # 汇总CSV（包含统计数据：平均值、标准差）
    echo "TestName,DataType,FileSizeKB,OriginalBytes,Method,AvgCompressedBytes,StdCompressedBytes,AvgCompressionRatio,StdCompressionRatio,AvgCompressTime_ms,StdCompressTime_ms,AvgDecompressTime_ms,StdDecompressTime_ms,SpaceSaving%,SpeedupCompress,SpeedupDecompress" > "$CSV_SUMMARY"
}

# 将测试结果追加到CSV
append_to_csv() {
    local timestamp=$1
    local run_id=$2
    local test_name=$3
    local data_type=$4
    local file_size_kb=$5
    local original_bytes=$6
    local method=$7
    local compressed_bytes=$8
    local compression_ratio=$9
    local compress_time=${10}
    local decompress_time=${11}
    local md5_verified=${12}
    
    echo "$timestamp,$run_id,$test_name,$data_type,$file_size_kb,$original_bytes,$method,$compressed_bytes,$compression_ratio,$compress_time,$decompress_time,$md5_verified" >> "$CSV_FILE"
}

# 计算统计数据（平均值和标准差）
calculate_statistics() {
    python3 << 'PYTHON_EOF'
import csv
import sys
from collections import defaultdict
import math

# 读取CSV数据
data = defaultdict(lambda: defaultdict(list))

with open('benchmark_results.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        key = (row['TestName'], row['DataType'], row['FileSizeKB'], row['Method'])
        data[key]['CompressedBytes'].append(float(row['CompressedBytes']))
        data[key]['CompressionRatio'].append(float(row['CompressionRatio']))
        data[key]['CompressTime_ms'].append(float(row['CompressTime_ms']))
        data[key]['DecompressTime_ms'].append(float(row['DecompressTime_ms']))
        data[key]['OriginalBytes'] = row['OriginalBytes']

# 计算平均值和标准差
def mean(values):
    return sum(values) / len(values) if values else 0

def std_dev(values):
    if len(values) < 2:
        return 0
    avg = mean(values)
    variance = sum((x - avg) ** 2 for x in values) / (len(values) - 1)
    return math.sqrt(variance)

# 按测试分组计算
results = defaultdict(dict)
for key, metrics in data.items():
    test_name, data_type, file_size, method = key
    test_key = (test_name, data_type, file_size)
    
    results[test_key][method] = {
        'avg_compressed': mean(metrics['CompressedBytes']),
        'std_compressed': std_dev(metrics['CompressedBytes']),
        'avg_ratio': mean(metrics['CompressionRatio']),
        'std_ratio': std_dev(metrics['CompressionRatio']),
        'avg_compress_time': mean(metrics['CompressTime_ms']),
        'std_compress_time': std_dev(metrics['CompressTime_ms']),
        'avg_decompress_time': mean(metrics['DecompressTime_ms']),
        'std_decompress_time': std_dev(metrics['DecompressTime_ms']),
        'original_bytes': metrics['OriginalBytes']
    }

# 写入汇总CSV
with open('benchmark_summary.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['TestName', 'DataType', 'FileSizeKB', 'OriginalBytes', 'Method', 
                     'AvgCompressedBytes', 'StdCompressedBytes', 'AvgCompressionRatio', 'StdCompressionRatio',
                     'AvgCompressTime_ms', 'StdCompressTime_ms', 'AvgDecompressTime_ms', 'StdDecompressTime_ms',
                     'SpaceSaving%', 'SpeedupCompress', 'SpeedupDecompress'])
    
    for test_key in sorted(results.keys()):
        test_name, data_type, file_size = test_key
        
        if 'Fixed' in results[test_key] and 'FastCDC' in results[test_key]:
            fixed = results[test_key]['Fixed']
            fastcdc = results[test_key]['FastCDC']
            
            # 计算节省和加速比
            space_saving = ((fixed['avg_compressed'] - fastcdc['avg_compressed']) / 
                           fixed['avg_compressed'] * 100) if fixed['avg_compressed'] > 0 else 0
            speedup_compress = (fixed['avg_compress_time'] / fastcdc['avg_compress_time']) if fastcdc['avg_compress_time'] > 0 else 0
            speedup_decompress = (fixed['avg_decompress_time'] / fastcdc['avg_decompress_time']) if fastcdc['avg_decompress_time'] > 0 else 0
            
            # 写入固定分块数据
            writer.writerow([
                test_name, data_type, file_size, fixed['original_bytes'], 'Fixed',
                f"{fixed['avg_compressed']:.2f}", f"{fixed['std_compressed']:.2f}",
                f"{fixed['avg_ratio']:.2f}", f"{fixed['std_ratio']:.2f}",
                f"{fixed['avg_compress_time']:.2f}", f"{fixed['std_compress_time']:.2f}",
                f"{fixed['avg_decompress_time']:.2f}", f"{fixed['std_decompress_time']:.2f}",
                '-', '-', '-'
            ])
            
            # 写入FastCDC数据
            writer.writerow([
                test_name, data_type, file_size, fastcdc['original_bytes'], 'FastCDC',
                f"{fastcdc['avg_compressed']:.2f}", f"{fastcdc['std_compressed']:.2f}",
                f"{fastcdc['avg_ratio']:.2f}", f"{fastcdc['std_ratio']:.2f}",
                f"{fastcdc['avg_compress_time']:.2f}", f"{fastcdc['std_compress_time']:.2f}",
                f"{fastcdc['avg_decompress_time']:.2f}", f"{fastcdc['std_decompress_time']:.2f}",
                f"{space_saving:.2f}", f"{speedup_compress:.2f}", f"{speedup_decompress:.2f}"
            ])

print("✓ 统计分析完成")
PYTHON_EOF
}

# 主测试函数（支持重复测试）
benchmark_test_repeated() {
    local test_name=$1
    local file_size=$2
    local data_type=$3
    local run_id=$4
    local file_name="${test_name}_${file_size}_run${run_id}"
    
    # 只在第一次运行时显示标题
    if [ $run_id -eq 1 ]; then
        echo -e "${BLUE}>>> 测试: $test_name (大小: ${file_size}KB, 类型: $data_type)${NC}"
        echo -e "${CYAN}    重复 $REPEAT_COUNT 次以确保结果稳定性...${NC}"
    fi
    
    echo -n "    运行 $run_id/$REPEAT_COUNT: "

    #bug in

    # 生成测试数据
    case $data_type in
        "random")
            dd if=/dev/urandom of="${file_name}.dat" bs=1024 count=$file_size 2>/dev/null
            ;;
        "pattern")
            python3 << EOF
with open('${file_name}.dat', 'wb') as f:
    pattern = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" * 100
    total_size = $file_size * 1024
    while f.tell() < total_size:
        f.write(pattern)
EOF
            ;;
        "mixed")
            python3 << EOF
import os
with open('${file_name}.dat', 'wb') as f:
    pattern = b"REPEATED_BLOCK_" * 64
    random_block = os.urandom(1024)
    total_size = $file_size * 1024
    while f.tell() < total_size:
        f.write(pattern)
        f.write(random_block)
EOF
            ;;
    esac
    
    local original_size=$(stat -c%s "${file_name}.dat")
    local orig_md5=$(md5sum "${file_name}.dat" | cut -d' ' -f1)
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # === 测试固定分块 ===
    # 使用 /usr/bin/time 进行精确计时（兼容 OpenCloudOS）
    # overlaybd-zfile 可能使用: <input> <output> 的格式（没有 compress 子命令）
    local time_output=$(/usr/bin/time -f "%e" $ZFILE "${file_name}.dat" "${file_name}_fixed.zfile" 2>&1)
    
    # 检查压缩是否成功
    if [ ! -f "${file_name}_fixed.zfile" ]; then
        echo -e "${RED}✗ 固定分块压缩失败${NC}"
        echo "错误信息: $time_output"
        echo "命令: $ZFILE ${file_name}.dat ${file_name}_fixed.zfile"
        return 1
    fi
    
    # 提取时间（最后一行应该是时间）
    local time_value=$(echo "$time_output" | grep "^[0-9]" | tail -1)
    local fixed_compress_time=$(echo "$time_value * 1000" | bc 2>/dev/null | cut -d'.' -f1)
    if [ -z "$fixed_compress_time" ]; then
        fixed_compress_time=0
    fi
    local fixed_size=$(stat -c%s "${file_name}_fixed.zfile")
    
    time_output=$(/usr/bin/time -f "%e" $ZFILE -x "${file_name}_fixed.zfile" "${file_name}_fixed_out.dat" 2>&1)
    
    # 检查解压缩是否成功
    if [ ! -f "${file_name}_fixed_out.dat" ]; then
        echo -e "${RED}✗ 固定分块解压缩失败${NC}"
        echo "错误信息: $time_output"
        return 1
    fi
    
    time_value=$(echo "$time_output" | grep "^[0-9]" | tail -1)
    local fixed_decompress_time=$(echo "$time_value * 1000" | bc 2>/dev/null | cut -d'.' -f1)
    if [ -z "$fixed_decompress_time" ]; then
        fixed_decompress_time=0
    fi
    
    local fixed_md5=$(md5sum "${file_name}_fixed_out.dat" | cut -d' ' -f1)
    local fixed_verified="true"
    if [ "$fixed_md5" != "$orig_md5" ]; then
        fixed_verified="false"
        echo -e "${RED}固定分块MD5失败!${NC}"
        return 1
    fi
    
    local fixed_ratio=$(echo "scale=4; $fixed_size * 100 / $original_size" | bc)
    
    # 保存固定分块数据到CSV
    append_to_csv "$timestamp" "$run_id" "$test_name" "$data_type" "$file_size" \
        "$original_size" "Fixed" "$fixed_size" "$fixed_ratio" \
        "$fixed_compress_time" "$fixed_decompress_time" "$fixed_verified"
    
    # === 测试FastCDC ===
    # 使用 /usr/bin/time 进行精确计时（兼容 OpenCloudOS）
    time_output=$(/usr/bin/time -f "%e" $ZFILE --fastcdc "${file_name}.dat" "${file_name}_fastcdc.zfile" 2>&1)
    
    # 检查压缩是否成功
    if [ ! -f "${file_name}_fastcdc.zfile" ]; then
        echo -e "${RED}✗ FastCDC 压缩失败${NC}"
        echo "错误信息: $time_output"
        return 1
    fi
    
    time_value=$(echo "$time_output" | grep "^[0-9]" | tail -1)
    local fastcdc_compress_time=$(echo "$time_value * 1000" | bc 2>/dev/null | cut -d'.' -f1)
    if [ -z "$fastcdc_compress_time" ]; then
        fastcdc_compress_time=0
    fi
    local fastcdc_size=$(stat -c%s "${file_name}_fastcdc.zfile")
    
    time_output=$(/usr/bin/time -f "%e" $ZFILE -x "${file_name}_fastcdc.zfile" "${file_name}_fastcdc_out.dat" 2>&1)
    
    # 检查解压缩是否成功
    if [ ! -f "${file_name}_fastcdc_out.dat" ]; then
        echo -e "${RED}✗ FastCDC 解压缩失败${NC}"
        echo "错误信息: $time_output"
        return 1
    fi
    
    time_value=$(echo "$time_output" | grep "^[0-9]" | tail -1)
    local fastcdc_decompress_time=$(echo "$time_value * 1000" | bc 2>/dev/null | cut -d'.' -f1)
    if [ -z "$fastcdc_decompress_time" ]; then
        fastcdc_decompress_time=0
    fi
    
    local fastcdc_md5=$(md5sum "${file_name}_fastcdc_out.dat" | cut -d' ' -f1)
    local fastcdc_verified="true"
    if [ "$fastcdc_md5" != "$orig_md5" ]; then
        fastcdc_verified="false"
        echo -e "${RED}FastCDC MD5失败!${NC}"
        return 1
    fi
    
    local fastcdc_ratio=$(echo "scale=4; $fastcdc_size * 100 / $original_size" | bc)
    
    # 保存FastCDC数据到CSV
    append_to_csv "$timestamp" "$run_id" "$test_name" "$data_type" "$file_size" \
        "$original_size" "FastCDC" "$fastcdc_size" "$fastcdc_ratio" \
        "$fastcdc_compress_time" "$fastcdc_decompress_time" "$fastcdc_verified"
    
    echo -e "${GREEN}✓${NC} (固定: ${fixed_compress_time}ms/${fixed_decompress_time}ms, FastCDC: ${fastcdc_compress_time}ms/${fastcdc_decompress_time}ms)"
    
    # 清理临时文件
    rm -f "${file_name}.dat" "${file_name}"_*.{zfile,dat}
}

# 运行测试套件
run_test_suite() {
    local test_name=$1
    local file_size=$2
    local data_type=$3
    
    for run in $(seq 1 $REPEAT_COUNT); do
        benchmark_test_repeated "$test_name" "$file_size" "$data_type" "$run"
    done
    echo ""
}

# ============ 主程序 ============

echo "========================================" | tee "$RESULT_FILE"
echo "FastCDC vs 固定分块性能对比测试 (高级版)" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "测试时间: $(date)" | tee -a "$RESULT_FILE"
echo "重复次数: $REPEAT_COUNT" | tee -a "$RESULT_FILE"
echo "CSV输出: $CSV_FILE" | tee -a "$RESULT_FILE"
echo "统计摘要: $CSV_SUMMARY" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# 初始化CSV文件
init_csv

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}测试 1: 随机数据（不可压缩）${NC}"
echo -e "${YELLOW}========================================${NC}"
run_test_suite "random_100k" 100 "random"
run_test_suite "random_1m" 1024 "random"
run_test_suite "random_10m" 10240 "random"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}测试 2: 重复模式数据（高可压缩）${NC}"
echo -e "${YELLOW}========================================${NC}"
run_test_suite "pattern_100k" 100 "pattern"
run_test_suite "pattern_1m" 1024 "pattern"
run_test_suite "pattern_10m" 10240 "pattern"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}测试 3: 混合数据（模拟真实场景）${NC}"
echo -e "${YELLOW}========================================${NC}"
run_test_suite "mixed_100k" 100 "mixed"
run_test_suite "mixed_1m" 1024 "mixed"
run_test_suite "mixed_10m" 10240 "mixed"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}正在计算统计数据...${NC}"
echo -e "${YELLOW}========================================${NC}"
calculate_statistics

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}测试完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "详细数据: ${CYAN}$CSV_FILE${NC}"
echo -e "统计摘要: ${CYAN}$CSV_SUMMARY${NC}"
echo ""
echo -e "${YELLOW}统计摘要预览:${NC}"
echo "----------------------------------------"

# 显示汇总表格
python3 << 'PYTHON_EOF'
import csv

with open('benchmark_summary.csv', 'r') as f:
    reader = csv.DictReader(f)
    print(f"{'测试名称':<20} {'方法':<10} {'平均压缩率':<12} {'空间节省':<12} {'解压加速':<12}")
    print("-" * 80)
    
    for row in reader:
        if row['Method'] == 'FastCDC':
            print(f"{row['TestName']:<20} {row['Method']:<10} "
                  f"{row['AvgCompressionRatio']:>6}%±{row['StdCompressionRatio']:>5}% "
                  f"{row['SpaceSaving%']:>8}% "
                  f"{row['SpeedupDecompress']:>8}x")
PYTHON_EOF

echo ""
echo -e "${CYAN}提示: 使用 Excel/LibreOffice 打开 CSV 文件进行详细分析${NC}"
echo ""

# 返回原始目录
cd - >/dev/null
