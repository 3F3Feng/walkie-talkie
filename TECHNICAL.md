# WolkieTalkie 技术方案文档

## 概述

本文档详细描述 WolkieTalkie（随行对讲）项目的三种技术实现方案，以及推荐架构选型。

---

## 方案对比总览

| 方案 | 技术栈 | 精度 | 功耗 | 设备要求 | 复杂度 |
|------|--------|------|------|----------|--------|
| **方案A** | NearbyInteraction (UWB) | <10cm | 中等 | iPhone 11+ | 低 |
| **方案B** | CoreBluetooth + RSSI | 1-3m | 低 | 通用 BLE | 中 |
| **方案C** | MultipeerConnectivity | 无测距 | 低 | iOS 7+ | 低 |

---

## 方案A：NearbyInteraction + UWB（推荐）

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS 应用层                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   SwiftUI    │  │ AudioEngine  │  │  PeerManager │      │
│  │ ContentView  │  │ (AVAudioSession│ │ (Multipeer) │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
└─────────┼─────────────────┼────────────────┼────────────────┘
          │                 │                │
┌─────────▼─────────────────▼────────────────▼────────────────┐
│                    ProximityManager                        │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                  NISession (UWB)                     │  │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐     │  │
│  │  │ Discovery│───→│   Device │───→│ Proximity│     │  │
│  │  │   Phase  │    │   List   │    │  Updates │     │  │
│  │  └──────────┘    └──────────┘    └──────────┘     │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    硬件层 (U1 Chip)                          │
│              UWB Radio ──→ Distance Calculation             │
└─────────────────────────────────────────────────────────────┘
```

### 核心算法

#### 1. 音量映射算法

```swift
// 非线性音量映射，提供更自然的听觉体验
func calculateVolume(distance: Double) -> Float {
    let minDistance: Double = 1.0      // 最近距离（最大音量）
    let maxDistance: Double = 10.0   // 最远距离（最小音量）
    let maxVolume: Float = 1.0       // 最大音量
    let minVolume: Float = 0.1       // 最小音量（阈值）
    
    // 指数衰减模型（更符合人耳听觉特性）
    if distance <= minDistance {
        return maxVolume
    } else if distance >= maxDistance {
        return minVolume
    } else {
        // 指数曲线: vol = max * e^(-k * d)
        let k = log(maxVolume / minVolume) / (maxDistance - minDistance)
        return maxVolume * Float(exp(-k * (distance - minDistance)))
    }
}
```

#### 2. 距离平滑滤波

```swift
// 滑动平均滤波器，减少 UWB 测距抖动
class DistanceSmoother {
    private var samples: [Double] = []
    private let maxSamples = 5
    
    func addSample(_ distance: Double) -> Double {
        samples.append(distance)
        if samples.count > maxSamples {
            samples.removeFirst()
        }
        // 移除异常值后取平均
        let filtered = removeOutliers(samples)
        return filtered.reduce(0, +) / Double(filtered.count)
    }
    
    private func removeOutliers(_ values: [Double]) -> [Double] {
        guard values.count >= 3 else { return values }
        let mean = values.reduce(0, +) / Double(values.count)
        let stdDev = sqrt(values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count))
        return values.filter { abs($0 - mean) <= 2 * stdDev }
    }
}
```

### 通信协议

```
┌──────────────────────────────────────────┐
│         MultipeerConnectivity 层          │
│        (用于传输音频和控制信令)            │
├──────────────────────────────────────────┤
│  Message Type  │  Payload               │
├──────────────────────────────────────────┤
│  AUDIO_DATA    │  [Audio Buffer]        │
│  PEER_INFO     │  {name, deviceId}      │
│  VOLUME_ACK    │  {targetVolume}        │
│  PING          │  {}                    │
└──────────────────────────────────────────┘
```

---

## 方案B：CoreBluetooth + RSSI（备选）

### 适用场景

- 不支持 UWB 的旧设备（iPhone X 及更早机型）
- 低功耗要求的场景
- 不需要厘米级精度的应用

### RSSI 到距离的转换

```swift
// 基于信号传播模型的距离估算
func distanceFromRSSI(rssi: Int, txPower: Int = -59) -> Double {
    /*
     * 公式: d = 10 ^ ((txPower - rssi) / (10 * n))
     * 
     * txPower: 1米处RSSI典型值 (-59 dBm for iPhone)
     * n: 环境衰减因子 (2.0 开放空间, 3.0 室内)
     */
    let n = 2.5  // 室内环境典型值
    let ratio = Double(txPower - rssi) / (10.0 * n)
    return pow(10, ratio)
}
```

### 数据包结构

```swift
struct BLEAdvertisingPacket {
    let serviceUUID: UUID = .walkieTalkieService
    let deviceId: String
    let currentVolume: Float
    let timestamp: Date
    
    func encode() -> Data {
        // CBPeripheralManager 广播数据
    }
}
```

---

## 方案C：MultipeerConnectivity + GPS（广域）

### 适用场景

- 超远距离（>30米）
- 户外开阔地带
- 不需要精确测距

### 融合定位策略

```swift
// 多源数据融合
enum ProximitySource {
    case uwb(NIDistance)           // 高精度 (<30m)
    case bleRSSI(Double)           // 中精度 (1-30m)
    case gpsDistance(Double)       // 低精度 (>30m)
}

class HybridProximityManager {
    func getCurrentProximity() -> Double? {
        // 优先级: UWB > BLE > GPS
        if let uwb = getUWBDistance() {
            return uwb
        } else if let ble = getBLERSSILevel() {
            return distanceFromRSSI(rssi: ble)
        } else {
            return getGPSDistance()
        }
    }
}
```

---

## 音频系统架构

### 低延迟音频链路

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   麦克风     │───→│  AudioEngine │───→│  Encoder     │
│(AVAudioInput)│    │(AVAudioSession)│   │(Opus/Linear)│
└──────────────┘    └──────────────┘    └──────┬───────┘
                                               │
                                               ▼
                              ┌──────────────────────────┐
                              │  MultipeerConnectivity   │
                              │       MCSession          │
                              └───────────┬──────────────┘
                                          │
                                          ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   扬声器     │←───│  AudioEngine │←───│  Decoder     │
│(AVAudioOutput)│    │              │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
```

### 音量控制实现

```swift
class VolumeController {
    private let audioSession = AVAudioSession.sharedInstance()
    
    func setOutputVolume(_ volume: Float) throws {
        // 注意: iOS 不允许直接设置系统音量
        // 通过 MPVolumeView 或实时调整音频增益
        try audioSession.setOutputVolume(volume)
    }
    
    func applyVolumeCurve(_ distance: Double) -> Float {
        // 应用听觉心理学曲线
        // 参考 ISO 226:2003 等响度曲线
        let baseVolume = calculateVolume(distance: distance)
        let psychoacousticBoost = distance < 3.0 ? 1.2 : 1.0
        return min(1.0, baseVolume * Float(psychoacousticBoost))
    }
}
```

---

## 推荐架构（三方案融合）

### 分层设计

```
┌─────────────────────────────────────────────┐
│               UI 层 (SwiftUI)               │
│    ContentView → DeviceList → AudioControls │
├─────────────────────────────────────────────┤
│              业务逻辑层                      │
│  ┌────────────┐    ┌────────────┐        │
│  │AudioManager│◄──►│PeerManager │        │
│  └─────┬──────┘    └──────┬─────┘        │
├────────┼──────────────────┼──────────────┤
│        ▼                  ▼               │
│   ┌──────────────────────────────┐       │
│   │    ProximityEngine           │       │
│   │  ┌─────────┐  ┌─────────┐   │       │
│   │  │ UWB     │  │ BLE     │   │       │
│   │  │ Manager │  │ Manager │   │       │
│   │  └────┬────┘  └────┬────┘   │       │
│   └───────┼────────────┼─────────┘       │
├───────────┼────────────┼────────────────┤
│           ▼            ▼                │
│    NearbyInteraction  CoreBluetooth    │
│         (U1 Chip)     (BLE Radio)      │
└─────────────────────────────────────────────┘
```

### 状态机设计

```swift
enum WalkieState {
    case idle           // 空闲待机
    case discovering    // 正在发现设备
    case connected      // 已连接设备
    case transmitting   // 正在对讲
    case error          // 错误状态
}

class WalkieStateMachine {
    private var currentState: WalkieState = .idle
    
    func transition(to newState: WalkieState) {
        guard canTransition(from: currentState, to: newState) else {
            print("Invalid state transition: \(currentState) -> \(newState)")
            return
        }
        currentState = newState
        notifyStateChange(newState)
    }
    
    private func canTransition(from: WalkieState, to: WalkieState) -> Bool {
        // 定义合法的状态转换
        let validTransitions: [WalkieState: [WalkieState]] = [
            .idle: [.discovering],
            .discovering: [.connected, .idle],
            .connected: [.transmitting, .idle],
            .transmitting: [.connected],
            .error: [.idle]
        ]
        return validTransitions[from]?.contains(to) ?? false
    }
}
```

---

## 性能优化策略

### 电池优化

```swift
// 动态调整扫描频率
class PowerOptimizer {
    private var scanInterval: TimeInterval = 0.1  // 默认100ms
    
    func optimize(for activity: UserActivity) {
        switch activity {
        case .idle:
            scanInterval = 1.0    // 降低频率
        case .walking:
            scanInterval = 0.1    // 正常频率
        case .running:
            scanInterval = 0.05   // 高频（快速接近场景）
        }
        updateScanInterval(scanInterval)
    }
}
```

### 网络优化

| 场景 | 策略 | 目的 |
|------|------|------|
| 近距离 (<3m) | 降低音频采样率 | 节省带宽 |
| 远距离 (>8m) | 启用丢包重传 | 保证通话质量 |
| 静止状态 | 减少测距频率 | 省电 |
| 移动状态 | 增加测距频率 | 快速响应距离变化 |

---

## 错误处理

### 常见错误码

| 错误码 | 描述 | 处理方案 |
|--------|------|----------|
| NI00x | UWB 不可用 | 回退到 BLE 方案 |
| BLE01 | 蓝牙未授权 | 弹窗引导用户开启 |
| AUD02 | 音频会话冲突 | 重新初始化 Audio Session |
| NET03 | 网络连接中断 | 自动重连（指数退避） |

```swift
enum WalkieTalkieError: String {
    case uwbUnavailable
    case bluetoothNotAuthorized
    case audioSessionFailure
    case networkDisconnected
}

extension WalkieTalkieError {
    var recoverable: Bool {
        switch self {
        case .uwbUnavailable: return true
        case .bluetoothNotAuthorized: return false
        case .audioSessionFailure: return true
        case .networkDisconnected: return true
        }
    }
}
```

---

## 技术决策记录

### 为什么选 UWB 而非 Bluetooth?

1. **精度要求**: 对讲音量需要 10cm 级别精度
2. **方向感知**: UWB 支持 AoA (到达角)，未来可扩展指向性
3. **抗干扰**: UWB 在 6.5GHz 频段，避开 WiFi/BLE 拥挤的 2.4GHz
4. **Apple 生态**: NI 框架深度集成 iOS，开发维护成本低

### 为什么用 MultipeerConnectivity 而非纯 BLE?

1. **传输带宽**: 对讲需要 ~64kbps 音频流
2. **连接稳定性**: Multipeer 管理连接状态机
3. **加密**: 自动使用 TLS 加密音频数据

---

## 未来扩展

- [ ] 设备方向指示（UWB AoA）
- [ ] 群组对讲（星型拓扑）
- [ ] 历史定位记录
- [ ] Apple Watch 支持

---

*Last updated: 2026-02-17 by 小龙虾*
