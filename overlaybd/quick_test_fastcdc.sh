#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     FastCDC 功能验证测试 - 新设备快速检测                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OVERLAYBD_BIN="/home/wfy/DADI_OverlayBD_demo/overlaybd/build/output/overlaybd-zfile"
TEST_DIR="./quick_test_fastcdc"

# 检查是否在 overlaybd 目录
if [ ! -f "CMakeLists.txt" ] || [ ! -d "src/overlaybd" ]; then
    echo "错误：请在 overlaybd 目录下运行此脚本"
    echo "正确路径应该是：/home/wfy/DADI_OverlayBD_demo/overlaybd"
    exit 1
fi

# 检查编译产物
echo "══════════════════════════════════════════════════════════════"
echo "  [1/6] 检查编译状态"
echo "══════════════════════════════════════════════════════════════"

if [ ! -f "$OVERLAYBD_BIN" ]; then
    echo -e "${RED}✗ 编译产物不存在${NC}"
    echo ""
    echo "请先编译项目："
    echo "  mkdir -p build && cd build"
    echo "  cmake -DCMAKE_BUILD_TYPE=Release .."
    echo "  make -j\$(nproc)"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ 找到 overlaybd-zfile${NC}"
    ls -lh "$OVERLAYBD_BIN"
fi

# 检查 FastCDC 支持
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  [2/6] 检查 FastCDC 支持"
echo "══════════════════════════════════════════════════════════════"

if $OVERLAYBD_BIN --help 2>&1 | grep -q "fastcdc"; then
    echo -e "${GREEN}✓ FastCDC 参数已集成${NC}"
    echo ""
    echo "支持的 FastCDC 参数："
    $OVERLAYBD_BIN --help 2>&1 | grep -A 1 "fastcdc" || true
else
    echo -e "${RED}✗ FastCDC 参数未找到${NC}"
    echo "编译可能未包含 FastCDC 支持，请重新编译"
    exit 1
fi

# 创建测试目录
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  [3/6] 准备测试环境"
echo "══════════════════════════════════════════════════════════════"

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "测试目录：$(pwd)"

# 生成测试数据
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  [4/6] 生成测试数据"
echo "══════════════════════════════════════════════════════════════"

# 测试 1: 小文件 (10KB)
echo "生成 10KB 测试文件..."
dd if=/dev/urandom of=test_10k.bin bs=1024 count=10 2>/dev/null
ORIGINAL_MD5_10K=$(md5sum test_10k.bin | awk '{print $1}')
echo "  原始文件: test_10k.bin (10KB)"
echo "  MD5: $ORIGINAL_MD5_10K"

# 测试 2: 中等文件 (1MB，混合数据)
echo ""
echo "生成 1MB 混合数据测试文件..."
{
    # 重复数据块
    for i in {1..128}; do
        echo "REPEATED_PATTERN_BLOCK_FOR_TESTING" | tr -d '\n'
        dd if=/dev/zero bs=1024 count=4 2>/dev/null
    done
    # 随机数据块
    dd if=/dev/urandom bs=1024 count=512 2>/dev/null
} > test_1m.bin
ORIGINAL_MD5_1M=$(md5sum test_1m.bin | awk '{print $1}')
echo "  原始文件: test_1m.bin (~1MB)"
echo "  MD5: $ORIGINAL_MD5_1M"

# 运行 FastCDC 压缩测试
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  [5/6] FastCDC 压缩与解压缩测试"
echo "══════════════════════════════════════════════════════════════"

#OVERLAYBD_BIN="../$OVERLAYBD_BIN"

# 测试 1: 10KB 文件
echo ""
echo "--- 测试 1: 10KB 文件 ---"
echo ""
echo "压缩中（使用 FastCDC）..."
if $OVERLAYBD_BIN --fastcdc test_10k.bin test_10k.zfile 2>&1; then
    echo -e "${GREEN}✓ 压缩成功${NC}"
    COMPRESSED_SIZE_10K=$(stat -f%z test_10k.zfile 2>/dev/null || stat -c%s test_10k.zfile)
    ORIGINAL_SIZE_10K=$(stat -f%z test_10k.bin 2>/dev/null || stat -c%s test_10k.bin)
    echo "  原始大小: $ORIGINAL_SIZE_10K bytes"
    echo "  压缩大小: $COMPRESSED_SIZE_10K bytes"
    RATIO_10K=$(echo "scale=2; $COMPRESSED_SIZE_10K * 100 / $ORIGINAL_SIZE_10K" | bc)
    echo "  压缩比: ${RATIO_10K}%"
else
    echo -e "${RED}✗ 压缩失败${NC}"
    exit 1
fi

echo ""
echo "解压缩中..."
if $OVERLAYBD_BIN -x test_10k.zfile test_10k_recovered.bin 2>&1; then
    echo -e "${GREEN}✓ 解压缩成功${NC}"
else
    echo -e "${RED}✗ 解压缩失败${NC}"
    exit 1
fi

echo ""
echo "验证数据完整性..."
RECOVERED_MD5_10K=$(md5sum test_10k_recovered.bin | awk '{print $1}')
if [ "$ORIGINAL_MD5_10K" == "$RECOVERED_MD5_10K" ]; then
    echo -e "${GREEN}✓ MD5 校验通过${NC}"
    echo "  原始:   $ORIGINAL_MD5_10K"
    echo "  恢复后: $RECOVERED_MD5_10K"
else
    echo -e "${RED}✗ MD5 校验失败${NC}"
    echo "  原始:   $ORIGINAL_MD5_10K"
    echo "  恢复后: $RECOVERED_MD5_10K"
    exit 1
fi

# 测试 2: 1MB 文件
echo ""
echo "--- 测试 2: 1MB 混合数据文件 ---"
echo ""
echo "压缩中（使用 FastCDC）..."
if $OVERLAYBD_BIN --fastcdc --cdc_min=2 --cdc_avg=8 --cdc_max=64 test_1m.bin test_1m.zfile 2>&1; then
    echo -e "${GREEN}✓ 压缩成功${NC}"
    COMPRESSED_SIZE_1M=$(stat -f%z test_1m.zfile 2>/dev/null || stat -c%s test_1m.zfile)
    ORIGINAL_SIZE_1M=$(stat -f%z test_1m.bin 2>/dev/null || stat -c%s test_1m.bin)
    echo "  原始大小: $ORIGINAL_SIZE_1M bytes"
    echo "  压缩大小: $COMPRESSED_SIZE_1M bytes"
    RATIO_1M=$(echo "scale=2; $COMPRESSED_SIZE_1M * 100 / $ORIGINAL_SIZE_1M" | bc)
    SAVING_1M=$(echo "scale=2; 100 - $RATIO_1M" | bc)
    echo "  压缩比: ${RATIO_1M}%"
    echo "  空间节省: ${SAVING_1M}%"
else
    echo -e "${RED}✗ 压缩失败${NC}"
    exit 1
fi

echo ""
echo "解压缩中..."
if $OVERLAYBD_BIN -x test_1m.zfile test_1m_recovered.bin 2>&1; then
    echo -e "${GREEN}✓ 解压缩成功${NC}"
else
    echo -e "${RED}✗ 解压缩失败${NC}"
    exit 1
fi

echo ""
echo "验证数据完整性..."
RECOVERED_MD5_1M=$(md5sum test_1m_recovered.bin | awk '{print $1}')
if [ "$ORIGINAL_MD5_1M" == "$RECOVERED_MD5_1M" ]; then
    echo -e "${GREEN}✓ MD5 校验通过${NC}"
    echo "  原始:   $ORIGINAL_MD5_1M"
    echo "  恢复后: $RECOVERED_MD5_1M"
else
    echo -e "${RED}✗ MD5 校验失败${NC}"
    echo "  原始:   $ORIGINAL_MD5_1M"
    echo "  恢复后: $RECOVERED_MD5_1M"
    exit 1
fi

# 对比测试：FastCDC vs 固定分块
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  [6/6] 对比测试: FastCDC vs 固定分块"
echo "══════════════════════════════════════════════════════════════"

echo ""
echo "使用固定分块压缩 1MB 文件..."
if $OVERLAYBD_BIN test_1m.bin test_1m_fixed.zfile 2>&1; then
    echo -e "${GREEN}✓ 固定分块压缩成功${NC}"
    COMPRESSED_SIZE_FIXED=$(stat -f%z test_1m_fixed.zfile 2>/dev/null || stat -c%s test_1m_fixed.zfile)
    RATIO_FIXED=$(echo "scale=2; $COMPRESSED_SIZE_FIXED * 100 / $ORIGINAL_SIZE_1M" | bc)
    echo "  压缩大小: $COMPRESSED_SIZE_FIXED bytes"
    echo "  压缩比: ${RATIO_FIXED}%"
else
    echo -e "${YELLOW}⚠ 固定分块压缩失败（可能正常）${NC}"
    COMPRESSED_SIZE_FIXED=0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    📊 测试结果汇总"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "测试文件 1: 10KB 随机数据"
echo "  ✓ FastCDC 压缩:    ${RATIO_10K}%"
echo "  ✓ MD5 校验:        通过"
echo ""
echo "测试文件 2: 1MB 混合数据"
echo "  ✓ FastCDC 压缩:    ${RATIO_1M}% (节省 ${SAVING_1M}%)"
if [ "$COMPRESSED_SIZE_FIXED" -gt 0 ]; then
    echo "  ✓ 固定分块压缩:    ${RATIO_FIXED}%"
    IMPROVEMENT=$(echo "scale=2; $RATIO_FIXED - $RATIO_1M" | bc)
    if (( $(echo "$IMPROVEMENT > 0" | bc -l) )); then
        echo "  ✓ FastCDC 优势:    ${IMPROVEMENT}% 更优"
    fi
fi
echo "  ✓ MD5 校验:        通过"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓✓✓ FastCDC 在新设备上运行正常！                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📁 测试文件保存在: $(pwd)"
echo ""
echo "下一步建议："
echo "  1. 运行完整测试: cd ../experiments/fastcdc_benchmark && bash comprehensive_test.sh"
echo "  2. 运行基准测试: bash benchmark_fastcdc_advanced.sh"
echo "  3. 清理测试文件: cd .. && rm -rf $TEST_DIR"
echo ""
echo "══════════════════════════════════════════════════════════════"