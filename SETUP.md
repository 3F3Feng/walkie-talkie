# WolkieTalkie 开发环境搭建指南

本指南帮助你从零开始搭建 WolkieTalkie 项目的开发环境。

---

## 系统要求

### 必需

| 项目 | 最低版本 | 推荐版本 |
|------|----------|----------|
| macOS | 13.0+ | 14.0+ |
| Xcode | 14.0+ | 15.0+ |
| iOS Deployment Target | 15.0 | 17.0 |

### 硬件要求

| 角色 | 设备要求 |
|------|----------|
| 开发者 | Mac with Apple Silicon/Intel |
| 测试设备 | iPhone 11 或更新机型 (需 U1 芯片) |

---

## 安装步骤

### 1. 安装 Xcode

**通过 App Store 安装**（推荐）

```bash
open https://apps.apple.com/app/xcode/id497799835
```

**通过命令行安装**（需 Xcode Command Line Tools）

```bash
xcode-select --install
```

验证安装:

```bash
xcode-select -p
# 输出: /Applications/Xcode.app/Contents/Developer
```

---

### 2. 克隆项目

```bash
# 进入工作目录
cd ~/Documents

# 克隆项目
git clone https://github.com/yourusername/wolkietalkie.git

# 进入项目目录
cd wolkietalkie
```

---

### 3. 项目结构确认

```
wolkietalkie/
├── README.md
├── TECHNICAL.md
├── API.md
├── SETUP.md
├── Info.plist
├── AppDelegate.swift
└── Sources/
    ├── AppDelegate.swift
    ├── ContentView.swift
    └── ProximityManager.swift
```

---

### 4. 配置代码签名

打开项目:

```bash
open -a Xcode .
```

在 Xcode 中:

1. 选择项目文件 `WolkieTalkie.xcodeproj`
2. 选择 Target → Signing & Capabilities
3. 配置:
   - **Team**: 添加你的 Apple ID
   - **Bundle Identifier**: `com.yourname.wolkietalkie`

---

### 5. 添加权限描述

确保 `Info.plist` 包含以下权限描述:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSNearbyInteractionUsageDescription</key>
    <string>应用需要使用附近交互功能检测设备间距离</string>
    
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>位置权限用于改进距离检测精度</string>
    
    <key>NSMicrophoneUsageDescription</key>
    <string>应用需要麦克风权限进行语音对讲</string>
    
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
</dict>
</plist>
```

---

### 6. 真机配置

**支持的设备**（必须有 U1 芯片）:

- iPhone 11 / 11 Pro / 11 Pro Max
- iPhone 12 全系列
- iPhone 13 全系列
- iPhone 14 全系列
- iPhone 15 全系列
- iPhone 16 全系列

**配置步骤**:

1. 用 USB-C/Lightning 线连接 iPhone
2. 在 Xcode 中选择你的设备作为目标
3. 信任开发者证书（首次运行时 iPhone 上会弹出提示）
4. 在 iPhone → 设置 → 通用 → VPN与设备管理中信任证书

---

## 运行测试

### 单机测试

```bash
# 构建并运行
xcodebuild -project WolkieTalkie.xcodeproj \
           -scheme WolkieTalkie \
           -destination 'platform=iOS,name=iPhone' \
           clean build
```

### 双设备测试（推荐）

1. 将两部 iPhone 都连接到 Mac
2. 在 Xcode 中依次选择目标设备
3. 分别运行应用到两台设备
4. 保持两台设备在 10 米范围内

---

## 调试配置

### 启用日志

在 Xcode 中设置环境变量:

```
Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables

添加: OS_ACTIVITY_MODE = disable
添加: NI_LOGGING = 1
```

### 使用无线调试

1. Xcode → Window → Devices and Simulators
2. 选中你的设备，勾选 "Connect via network"
3. 断开 USB 线，设备仍保持连接
4. 现在可以无线调试

---

## 常见问题

### 问题 1: "Unable to locate NearbyInteraction"

**原因**: Target iOS 版本低于 15.0

**解决**:

```
Project → Build Settings → iOS Deployment Target → 15.0
```

### 问题 2: "No such module 'NearbyInteraction'"

**原因**: 在 iOS Simulator 上运行

**解决**: 必须在真机上测试，模拟器不支持 UWB

### 问题 3: "NSNearbyInteractionUsageDescription missing"

**解决**: 在 Info.plist 中添加权限描述

### 问题 4: 音量未自动调节

**检查项**:
1. 两设备是否都在运行应用？
2. 是否在 10 米范围内？
3. UWB 是否被环境干扰？

---

## 构建发布版本

### 配置 App Store 打包

```bash
# 归档
xcodebuild archive \
    -project WolkieTalkie.xcodeproj \
    -scheme WolkieTalkie \
    -archivePath build/WolkieTalkie.xcarchive \
    -destination 'generic/platform=iOS'

# 导出 IPA
xcodebuild -exportArchive \
    -archivePath build/WolkieTalkie.xcarchive \
    -exportPath build \
    -exportOptionsPlist exportOptions.plist
```

---

## 开发工作流

### Git 提交规范

```bash
# 功能分支
git checkout -b feature/audio-optimization

# 提交规范
git commit -m "feat: 添加音频降噪算法"
git commit -m "fix: 修复距离计算溢出"
git commit -m "docs: 更新 API 文档"
```

---

## 资源链接

- [Apple Nearby Interaction Docs](https://developer.apple.com/documentation/nearbyinteraction)
- [MultipeerConnectivity Guide](https://developer.apple.com/documentation/multipeerconnectivity)
- [AVAudioSession Best Practices](https://developer.apple.com/documentation/avfoundation/avaudiosession)

---

## 快速检查清单

- [ ] macOS 13.0+
- [ ] Xcode 14.0+ 已安装
- [ ] Apple Developer Account 已配置
- [ ] iPhone 11+ 真机已连接
- [ ] 代码签名配置完成
- [ ] Info.plist 权限已添加
- [ ] 两台设备测试通过

---

*Last updated: 2026-02-17*
