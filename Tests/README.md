# WalkieTalkie 测试指南

## 在 Xcode 中添加测试

### 1. 创建 Unit Test Target
```bash
# 在 Xcode 中：
# File → New → Target
# 选择 "Unit Testing Bundle"
# Product Name: WolkieTalkieTests
```

### 2. 添加测试文件
将以下文件拖入 Tests 目录：
- `Tests/UnitTests/ProximityManagerTests.swift`
- `Tests/UnitTests/TrackedDeviceTests.swift`

### 3. 运行测试
```bash
# 命令行
xcodebuild test -project WolkieTalkie.xcodeproj -scheme WolkieTalkie -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 或在 Xcode 中
Cmd + U
```

## 测试覆盖

### 已包含测试
- ✅ 距离计算 (RSSI → 距离转换)
- ✅ 设备过滤 (< 50m)
- ✅ 设备排序 (按距离)
- ✅ 配对状态转换
- ✅ App Mode 切换
- ✅ Talk Mode 切换

### 待添加测试
- [ ] BLE 连接测试
- [ ] 音频录制测试
- [ ] 音频播放测试
- [ ] UWB Token 交换测试

## GitHub Actions CI

CI 配置已创建：`.github/workflows/ci.yml`

### 自动运行
- 每次 push 到 main
- 每次 Pull Request

### CI 包含
- ✅ 单元测试
- ✅ iOS Simulator 构建
- ✅ iOS Device 构建 (archive)

### 查看结果
https://github.com/YOUR_USERNAME/walkie-talkie/actions
