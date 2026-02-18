# WolkieTalkie - 智能对讲机

一个基于 Nearby Interaction 框架的 iOS 智能对讲机应用，能够根据设备之间的物理距离自动调节音量。

## 功能特性

- **智能距离感应** - 使用 U1 芯片和 Nearby Interaction 框架实时检测设备间距离
- **自动音量调节** - 距离越近，音量越小；距离越远，音量越大
- **低延迟通信** - 利用 UWB (Ultra Wideband) 技术实现精准测距
- **简洁 UI** - 原生 SwiftUI 实现的直观界面

## 系统要求

- **iOS** 15.0+
- **设备** iPhone 11 或更新机型 (需 U1 芯片)
- **开发环境** Xcode 14.0+

## 快速开始

### 安装

```bash
git clone https://github.com/yourusername/wolkietalkie.git
cd wolkietalkie
open WolkieTalkie.xcodeproj
```

### 使用步骤

1. 在两台 iPhone 上分别启动应用
2. 点击 "Start Detection" 开始设备发现
3. 应用自动检测附近设备并开始调节音量
4. 观察屏幕显示的距离和音量百分比

## 原理

```
┌─────────────┐      UWB (U1 Chip)      ┌─────────────┐
│   iPhone A  │ ◄──────────────────► │   iPhone B  │
│  ┌─────────┐│                        │┌─────────┐  │
│  │ NISession││                        ││NISession│  │
│  │  .proximity│◄─── RSSI / Distance ─►││.proximity │  │
│  └────┬────┘│                        │└────┬────┘  │
│       │     │                        │     │       │
│  ┌────▼────┐│                        │┌────▼────┐   │
│  │Volume   ││                        ││Volume   │   │
│  │Controller│                        │ │Controller│   │
│  └─────────┘│                        │ └─────────┘   │
└─────────────┘                        └───────────────┘
```

## 项目结构

```
wolkietalkie/
├── README.md                 # 项目说明文档
├── TECHNICAL.md              # 技术架构文档
├── API.md                    # API 参考文档
├── SETUP.md                  # 开发环境搭建指南
├── Info.plist                # 应用配置
├── AppDelegate.swift         # 应用入口
└── Sources/
    ├── AppDelegate.swift     # 应用委托
    ├── ContentView.swift     # 主界面视图
    └── ProximityManager.swift # 距离感应核心模块
```

## 依赖框架

- **NearbyInteraction** - Apple UWB 近场交互框架
- **CoreLocation** - 定位权限管理
- **AVFoundation** - 音频系统控制
- **SwiftUI** - 用户界面

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 致谢

- Apple Nearby Interaction Framework
- iOS Developer Community

---

*Made with by 老张*
