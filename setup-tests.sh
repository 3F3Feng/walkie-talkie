#!/bin/bash

# WalkieTalkie 测试自动配置脚本

echo "🧪 配置单元测试..."

# 检查测试文件是否存在
echo "检查测试文件..."
if [ -d "Tests/UnitTests" ]; then
    echo "✅ 找到测试目录"
    ls -la Tests/UnitTests/
else
    echo "❌ 测试目录不存在"
    exit 1
fi

# 检查是否有 Test Target
echo ""
echo "⚠️  你需要在 Xcode 中手动添加 Test Target："
echo ""
echo "1. 打开 WolkieTalkie.xcodeproj"
echo "2. File → New → Target"
echo "3. 选择 'Unit Testing Bundle'"
echo "4. Product Name: WolkieTalkieTests"
echo "5. 点击 Finish"
echo ""
echo "6. 将以下测试文件添加到 Test Target："
for file in Tests/UnitTests/*.swift; do
    if [ -f "$file" ]; then
        echo "   - $(basename $file)"
    fi
done
echo ""
echo "7. 确保每个测试文件顶部有：@testable import WolkieTalkie"
echo ""
echo "8. Cmd + U 运行测试"
echo ""

# 生成测试报告目录
mkdir -p TestReports
echo "✅ TestReports 目录已创建"

# 检查测试 coverage
echo ""
echo "📊 测试覆盖率检查："
echo "已实现的测试："
echo "  ✓ ProximityManagerTests - 距离计算、设备过滤、排序"
echo "  ✓ TrackedDeviceTests - 设备初始化、状态"
echo ""
echo "待实现（建议）："
echo "  ⏳ BLEManagerTests - 蓝牙连接、发现"
echo "  ⏳ AudioTests - 音频录制、播放"
echo "  ⏳ PairingTests - 配对流程"
echo ""
