# WolkieTalkie API 文档

## 核心类接口

---

### ProximityManager

距离感应管理器，处理 UWB 近场交互和设备发现。

```swift
class ProximityManager: NSObject, ObservableObject
```

#### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `shared` | `ProximityManager` | 单例实例 |
| `distance` | `Published<Double>` | 当前测得的距离（米） |
| `volume` | `Published<Float>` | 计算后的音量（0.0-1.0） |

#### 方法

##### `startDiscovery()`

开始发现附近的设备。

```swift
func startDiscovery()
```

**说明**: 初始化 NISession 并开始扫描 UWB 信号。

**使用示例**:
```swift
ProximityManager.shared.startDiscovery()
```

---

##### `stopDiscovery()`

停止设备发现。

```swift
func stopDiscovery()
```

---

##### `updateAudioVolume(_:)`

根据距离更新系统音量。

```swift
private func updateAudioVolume(_ distance: Double)
```

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `distance` | `Double` | 距离值（米） |

**实现细节**:
```swift
// 音量计算公式
volume = baseVolume * (1.0 - (distance * 0.5))
```

---

### ContentView

主界面视图，SwiftUI 实现。

```swift
struct ContentView: View
```

#### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `distance` | `State<Double>` | 显示的距离值 |
| `volume` | `State<Float>` | 显示音量百分比 |
| `isMonitoring` | `State<Bool>` | 是否正在监控 |

#### 方法

##### `setupNearbyDetection()`

初始化 Nearby Interaction 功能。

```swift
private func setupNearbyDetection()
```

**权限要求**:
- `NSNearbyInteractionUsageDescription` - 需要在 Info.plist 中声明
- `NSLocationWhenInUseUsageDescription` - 位置权限

---

##### `calculateVolume(distance:)`

计算基于距离的音量值。

```swift
private func calculateVolume(distance: Double) -> Float
```

**参数**:
| 参数 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `distance` | `Double` | 0.0 - +∞ | 输入距离 |

**返回值**: `Float` - 计算的音量值 (0.1 - 1.0)

**算法**:
```swift
// 线性插值
if distance < minDistance {
    return maxVolume
} else if distance > maxDistance {
    return minVolume
} else {
    return maxVolume - (maxVolume - minVolume) * 
           (distance - minDistance) / (maxDistance - minDistance)
}
```

---

##### `calculateDistance(rssi:)`

通过 RSSI 信号强度估算距离。

```swift
private func calculateDistance(rssi: Int16) -> Double
```

**参数**:
| 参数 | 类型 | 描述 |
|------|------|------|
| `rssi` | `Int16` | 信号强度值 (dBm) |

**公式**:
```
d = 10 ^ ((RSSI_1m - RSSI) / (10 * n))
```

其中:
- `RSSI_1m = -40dBm` (1米处的信号强度)
- `n = 2.0-3.0` (环境衰减因子)

---

## NearbyInteraction 框架

### NISession

Apple 的 Nearby Interaction 会话管理类。

```swift
class NISession: NSObject
```

#### 关键方法

| 方法 | 描述 |
|------|------|
| `run(_:)` | 启动附近交互会话 |
| `pause()` | 暂停会话 |
| `invalidate()` | 结束会话 |

#### 委托回调

```swift
protocol NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject])
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason)
    func session(_ session: NISession, didInvalidateWith error: Error)
}
```

---

### NINearbyObject

表示一个附近的交互设备。

| 属性 | 类型 | 描述 |
|------|------|------|
| `discoveryToken` | `NIDiscoveryToken` | 唯一标识符 |
| `distance` | `Float?` | 距离（米），可能为 nil |
| `direction` | `simd_float3?` | 方向向量（相对于设备） |

---

## 音频控制接口

### AVAudioSession

系统音频会话管理。

#### 配置音频

```swift
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth])
try audioSession.setActive(true)
```

#### 音量控制

```swift
// 获取当前音量
let currentVolume = audioSession.outputVolume

// 设置音量（需要导入 MediaPlayer）
try audioSession.setOutputVolume(0.7)
```

---

## 完整示例代码

### 启动对讲功能

```swift
import SwiftUI
import NearbyInteraction
import AVFoundation

@main
struct WalkItalkiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 配置音频会话
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio configuration failed: \(error)")
        }
        
        return true
    }
}

// MARK: - 主界面
struct ContentView: View {
    @State private var distance: Double = 0
    @State private var volume: Float = 0.5
    @State private var isMonitoring = false
    @StateObject private var proximityManager = ProximityManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // 距离显示
            VStack {
                Text("\(String(format: "%.2f", distance)) m")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                Text("当前距离")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            // 音量显示
            VStack {
                Text("\(Int(volume * 100))%")
                    .font(.title)
                ProgressView(value: Double(volume))
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 200)
                Text("自动调节音量")
                    .foregroundColor(.secondary)
            }
            
            // 控制按钮
            Button(action: {
                isMonitoring ? stopMonitoring() : startMonitoring()
            }) {
                HStack {
                    Image(systemName: isMonitoring ? "stop.circle" : "play.circle")
                    Text(isMonitoring ? "停止" : "开始对讲")
                }
                .font(.title2)
                .padding()
                .background(isMonitoring ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .onReceive(proximityManager.$distance) { newDistance in
            distance = newDistance
            volume = calculateVolume(distance: newDistance)
        }
        .onReceive(proximityManager.$volume) { newVolume in
            volume = newVolume
        }
    }
    
    private func startMonitoring() {
        ProximityManager.shared.startDiscovery()
        isMonitoring = true
    }
    
    private func stopMonitoring() {
        ProximityManager.shared.stopDiscovery()
        isMonitoring = false
        distance = 0
        volume = 0.5
    }
    
    private func calculateVolume(distance: Double) -> Float {
        let minDistance: Double = 1.0
        let maxDistance: Double = 10.0
        let maxVolume: Float = 1.0
        let minVolume: Float = 0.1
        
        if distance < minDistance {
            return maxVolume
        } else if distance > maxDistance {
            return minVolume
        } else {
            return maxVolume - (maxVolume - minVolume) *
                   Float((distance - minDistance) / (maxDistance - minDistance))
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
```

---

## 配置参考

### Info.plist 必需项

```xml
<key>NSNearbyInteractionUsageDescription</key>
<string>应用需要使用附近交互功能来检测距离</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>位置权限用于改进距离检测精度</string>

<key>NSMicrophoneUsageDescription</key>
<string>应用需要麦克风权限进行语音对讲</string>
```

---

## 类型定义

### 距离等级

```swift
enum DistanceLevel: String, CaseIterable {
    case veryNear   // < 1m
    case near       // 1-3m
    case medium     // 3-6m
    case far        // 6-10m
    case veryFar    // > 10m
    
    var description: String {
        switch self {
        case .veryNear: return "非常近"
        case .near: return "近"
        case .medium: return "中等"
        case .far: return "远"
        case .veryFar: return "非常远"
        }
    }
}
```

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-02-17 | 初始 API 文档 |

---

*API 版本: 1.0.0*