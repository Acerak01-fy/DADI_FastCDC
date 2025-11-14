#!/bin/bash

# FastCDC vs 固定大小分块性能对比测试

set -e

ZFILE=/home/wfy/DADI_OverlayBD_demo/overlaybd/build/output/overlaybd-zfile
WORK_DIR=/home/wfy/DADI_OverlayBD_demo/experiments/fastcdc_benchmark
RESULT_FILE="$WORK_DIR/benchmark_results.txt"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建工作目录
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "========================================" | tee "$RESULT_FILE"
echo "FastCDC vs 固定分块性能对比测试" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "测试时间: $(date)" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# 测试函数
benchmark_test() {
    local test_name=$1
    local file_size=$2
    local data_type=$3
    local file_name="${test_name}_${file_size}"
    
    echo -e "${BLUE}>>> 测试: $test_name (大小: $file_size)${NC}" | tee -a "$RESULT_FILE"
    
    # 生成测试数据
    case $data_type in
        "random")
            dd if=/dev/urandom of="${file_name}.dat" bs=1024 count=$file_size 2>/dev/null
            ;;
        "pattern")
            # 生成重复模式数据（高压缩率）
            python3 << EOF
with open('${file_name}.dat', 'wb') as f:
    pattern = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" * 100
    total_size = $file_size * 1024
    while f.tell() < total_size:
        f.write(pattern)
EOF
            ;;
        "mixed")
            # 混合数据：部分重复，部分随机
            python3 << EOF
import os
with open('${file_name}.dat', 'wb') as f:
    pattern = b"REPEATED_BLOCK_" * 64  # 1KB 重复块
    random_block = os.urandom(1024)     # 1KB 随机块
    total_size = $file_size * 1024
    while f.tell() < total_size:
        f.write(pattern)
        f.write(random_block)
EOF
            ;;
    esac
    
    local original_size=$(stat -c%s "${file_name}.dat")
    
    # 测试固定大小分块（默认）
    echo -n "  [固定分块] 压缩..." | tee -a "$RESULT_FILE"
    local fixed_start=$(date +%s%N)
    $ZFILE "${file_name}.dat" "${file_name}_fixed.zfile" 2>/dev/null
    local fixed_compress_time=$(( ($(date +%s%N) - $fixed_start) / 1000000 ))
    local fixed_size=$(stat -c%s "${file_name}_fixed.zfile")
    
    echo -n " 解压..." | tee -a "$RESULT_FILE"
    local fixed_decomp_start=$(date +%s%N)
    $ZFILE -x "${file_name}_fixed.zfile" "${file_name}_fixed_out.dat" 2>/dev/null
    local fixed_decompress_time=$(( ($(date +%s%N) - $fixed_decomp_start) / 1000000 ))
    
    # 验证正确性
    local fixed_md5=$(md5sum "${file_name}_fixed_out.dat" | cut -d' ' -f1)
    local orig_md5=$(md5sum "${file_name}.dat" | cut -d' ' -f1)
    if [ "$fixed_md5" != "$orig_md5" ]; then
        echo -e " ${RED}✗ 失败${NC}" | tee -a "$RESULT_FILE"
        return 1
    fi
    echo -e " ${GREEN}✓${NC}" | tee -a "$RESULT_FILE"
    
    # 测试 FastCDC 分块
    echo -n "  [FastCDC]   压缩..." | tee -a "$RESULT_FILE"
    local fastcdc_start=$(date +%s%N)
    $ZFILE --fastcdc "${file_name}.dat" "${file_name}_fastcdc.zfile" 2>/dev/null
    local fastcdc_compress_time=$(( ($(date +%s%N) - $fastcdc_start) / 1000000 ))
    local fastcdc_size=$(stat -c%s "${file_name}_fastcdc.zfile")
    
    echo -n " 解压..." | tee -a "$RESULT_FILE"
    local fastcdc_decomp_start=$(date +%s%N)
    $ZFILE -x "${file_name}_fastcdc.zfile" "${file_name}_fastcdc_out.dat" 2>/dev/null
    local fastcdc_decompress_time=$(( ($(date +%s%N) - $fastcdc_decomp_start) / 1000000 ))
    
    # 验证正确性
    local fastcdc_md5=$(md5sum "${file_name}_fastcdc_out.dat" | cut -d' ' -f1)
    if [ "$fastcdc_md5" != "$orig_md5" ]; then
        echo -e " ${RED}✗ 失败${NC}" | tee -a "$RESULT_FILE"
        return 1
    fi
    echo -e " ${GREEN}✓${NC}" | tee -a "$RESULT_FILE"
    
    # 计算统计数据
    local fixed_ratio=$(echo "scale=2; $fixed_size * 100 / $original_size" | bc)
    local fastcdc_ratio=$(echo "scale=2; $fastcdc_size * 100 / $original_size" | bc)
    local size_saving=$(echo "scale=2; ($fixed_size - $fastcdc_size) * 100 / $fixed_size" | bc)
    local compress_speedup=$(echo "scale=2; $fixed_compress_time / $fastcdc_compress_time" | bc)
    local decompress_speedup=$(echo "scale=2; $fixed_decompress_time / $fastcdc_decompress_time" | bc)
    
    # 输出结果
    echo "" | tee -a "$RESULT_FILE"
    echo "  原始大小:     $(numfmt --to=iec $original_size)" | tee -a "$RESULT_FILE"
    echo "  ----------------------------------------" | tee -a "$RESULT_FILE"
    printf "  %-20s %-15s %-15s %-15s\n" "指标" "固定分块" "FastCDC" "提升" | tee -a "$RESULT_FILE"
    echo "  ----------------------------------------" | tee -a "$RESULT_FILE"
    printf "  %-20s %-15s %-15s %-15s\n" "压缩后大小" "$(numfmt --to=iec $fixed_size)" "$(numfmt --to=iec $fastcdc_size)" "$([ $(echo "$size_saving > 0" | bc) -eq 1 ] && echo "+${size_saving}%" || echo "${size_saving}%")" | tee -a "$RESULT_FILE"
    printf "  %-20s %-15s %-15s %-15s\n" "压缩率" "${fixed_ratio}%" "${fastcdc_ratio}%" "-" | tee -a "$RESULT_FILE"
    printf "  %-20s %-15s %-15s %-15s\n" "压缩时间" "${fixed_compress_time}ms" "${fastcdc_compress_time}ms" "${compress_speedup}x" | tee -a "$RESULT_FILE"
    printf "  %-20s %-15s %-15s %-15s\n" "解压时间" "${fixed_decompress_time}ms" "${fastcdc_decompress_time}ms" "${decompress_speedup}x" | tee -a "$RESULT_FILE"
    echo "" | tee -a "$RESULT_FILE"
    
    # 清理临时文件
    rm -f "${file_name}.dat" "${file_name}"_*.{zfile,dat}
}

# 测试用例
echo "========================================" | tee -a "$RESULT_FILE"
echo "测试 1: 随机数据（不可压缩）" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
benchmark_test "random_100k" 100 "random"
benchmark_test "random_1m" 1024 "random"
benchmark_test "random_10m" 10240 "random"

echo "" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "测试 2: 重复模式数据（高可压缩）" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
benchmark_test "pattern_100k" 100 "pattern"
benchmark_test "pattern_1m" 1024 "pattern"
benchmark_test "pattern_10m" 10240 "pattern"

echo "" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "测试 3: 混合数据（模拟真实场景）" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
benchmark_test "mixed_100k" 100 "mixed"
benchmark_test "mixed_1m" 1024 "mixed"
benchmark_test "mixed_10m" 10240 "mixed"

echo "" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "测试 4: 实际文件（如果存在）" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"

# 测试实际的二进制文件
if [ -f /bin/bash ]; then
    echo -e "${BLUE}>>> 测试: 系统二进制文件 (/bin/bash)${NC}" | tee -a "$RESULT_FILE"
    cp /bin/bash test_bash.dat
    
    # 固定分块
    echo -n "  [固定分块] 压缩..." | tee -a "$RESULT_FILE"
    $ZFILE test_bash.dat test_bash_fixed.zfile 2>/dev/null
    echo -e " ${GREEN}✓${NC}" | tee -a "$RESULT_FILE"
    
    # FastCDC
    echo -n "  [FastCDC]   压缩..." | tee -a "$RESULT_FILE"
    $ZFILE --fastcdc test_bash.dat test_bash_fastcdc.zfile 2>/dev/null
    echo -e " ${GREEN}✓${NC}" | tee -a "$RESULT_FILE"
    
    bash_orig=$(stat -c%s test_bash.dat)
    bash_fixed=$(stat -c%s test_bash_fixed.zfile)
    bash_fastcdc=$(stat -c%s test_bash_fastcdc.zfile)
    bash_saving=$(echo "scale=2; ($bash_fixed - $bash_fastcdc) * 100 / $bash_fixed" | bc)
    
    echo "" | tee -a "$RESULT_FILE"
    echo "  原始大小:     $(numfmt --to=iec $bash_orig)" | tee -a "$RESULT_FILE"
    echo "  固定分块:     $(numfmt --to=iec $bash_fixed) ($(echo "scale=2; $bash_fixed*100/$bash_orig" | bc)%)" | tee -a "$RESULT_FILE"
    echo "  FastCDC:      $(numfmt --to=iec $bash_fastcdc) ($(echo "scale=2; $bash_fastcdc*100/$bash_orig" | bc)%)" | tee -a "$RESULT_FILE"
    echo "  空间节省:     ${bash_saving}%" | tee -a "$RESULT_FILE"
    echo "" | tee -a "$RESULT_FILE"
    
    rm -f test_bash.*
fi

echo "========================================" | tee -a "$RESULT_FILE"
echo "测试完成！" | tee -a "$RESULT_FILE"
echo "========================================" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"
echo -e "${GREEN}完整结果已保存到: $RESULT_FILE${NC}"
echo ""
echo "总结："
grep -E "提升|压缩率|空间节省" "$RESULT_FILE" | tail -20

# 返回原始目录
cd - >/dev/null
