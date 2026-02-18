import Foundation
import NearbyInteraction
import CoreBluetooth
import Combine
import AVFoundation
import simd
import MultipeerConnectivity

// MARK: - 协议定义
protocol ProximityProvider {
    var distance: Double { get }
    var isAvailable: Bool { get }
    func start() throws
    func stop()
}

// MARK: - 距离等级枚举
enum DistanceLevel: String, CaseIterable {
    case veryNear = "非常近"
    case near = "近"
    case medium = "中等"
    case far = "远"
    case veryFar = "非常远"
    case unknown = "未知"
    
    init(distance: Double) {
        switch distance {
        case 0..<1: self = .veryNear
        case 1..<3: self = .near
        case 3..<6: self = .medium
        case 6..<10: self = .far
        case 10...: self = .veryFar
        default: self = .unknown
        }
    }
}

// MARK: - Provider 类型（用于区分测距方式）
enum ProviderType: String {
    case uwb = "UWB"
    case bluetooth = "蓝牙"
}

// MARK: - 设备连接状态
enum DeviceConnectionState: String {
    case connecting = "连接中"
    case connected = "已连接"
    case disconnected = "已断开"
    
    var displayText: String { rawValue }
}

// MARK: - 追踪的设备模型
class TrackedDevice: Identifiable, ObservableObject {
    let id: String
    let peerID: MCPeerID
    let displayName: String
    
    @Published var connectionState: DeviceConnectionState = .connecting
    @Published var distance: Double = 0.0
    @Published var distanceLevel: DistanceLevel = .unknown
    @Published var volume: Float = 0.5
    @Published var providerType: ProviderType = .bluetooth
    @Published var rssi: Int = -50
    @Published var lastSeen: Date = Date()
    
    // UWB Token（用于 UWB 测距）
    var niToken: NIDiscoveryToken?
    
    init(peerID: MCPeerID) {
        self.id = peerID.displayName
        self.peerID = peerID
        self.displayName = peerID.displayName
    }
}

// MARK: - 应用状态
enum WalkieState: String {
    case idle = "空闲"
    case discovering = "发现中"
    case connected = "已连接"
    case transmitting = "对讲中"
    case error = "错误"
}

// MARK: - 错误定义
enum WalkieTalkieError: Error, LocalizedError {
    case uwbUnavailable
    case bluetoothNotAuthorized
    case audioSessionFailure
    case deviceNotSupported
    
    var errorDescription: String? {
        switch self {
        case .uwbUnavailable:
            return "您的设备不支持 UWB 超宽带技术，将使用蓝牙模式"
        case .bluetoothNotAuthorized:
            return "需要蓝牙权限来发现附近设备"
        case .audioSessionFailure:
            return "音频会话配置失败"
        case .deviceNotSupported:
            return "您的设备不支持此功能"
        }
    }
}

// MARK: - 音频控制器
class AudioController {
    private let audioSession = AVAudioSession.sharedInstance()
    private var currentVolume: Float = 0.5
    
    func configureAudioSession() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]
        )
        try audioSession.setActive(true)
    }
    
    /// 计算音量（指数衰减模型，更符合人耳听觉特性）
    func calculateVolume(distance: Double, 
                        minDistance: Double = 1.0,
                        maxDistance: Double = 10.0,
                        minVolume: Float = 0.1,
                        maxVolume: Float = 1.0) -> Float {
        guard distance > 0 else { return maxVolume }
        
        if distance <= minDistance {
            return maxVolume
        } else if distance >= maxDistance {
            return minVolume
        } else {
            // 指数衰减
            let k = log(Double(maxVolume / minVolume)) / (maxDistance - minDistance)
            return maxVolume * Float(exp(-k * (distance - minDistance)))
        }
    }
    
    func applyVolume(_ volume: Float) {
        // 注意：iOS 不允许直接设置系统音量
        // 实际项目中应使用 MPVolumeView 或调整音频增益
        currentVolume = max(0.0, min(1.0, volume))
        print("[Audio] Volume set to \(Int(currentVolume * 100))%")
    }
}

// MARK: - 距离平滑滤波器
class DistanceSmoother {
    private var samples: [Double] = []
    private let maxSamples = 5
    
    func addSample(_ distance: Double) -> Double {
        samples.append(distance)
        if samples.count > maxSamples {
            samples.removeFirst()
        }
        return smoothedValue()
    }
    
    private func smoothedValue() -> Double {
        guard samples.count >= 3 else {
            return samples.last ?? 0.0
        }
        
        // 移除异常值
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { pow($0 - mean, 2) }.reduce(0, +) / Double(samples.count)
        let stdDev = sqrt(variance)
        
        let filtered = samples.filter { abs($0 - mean) <= 2 * stdDev }
        return filtered.isEmpty ? mean : filtered.reduce(0, +) / Double(filtered.count)
    }
    
    func reset() {
        samples.removeAll()
    }
}

// MARK: - UWB 提供者（方案A）
class UWBProximityProvider: NSObject, ProximityProvider {
    static let shared = UWBProximityProvider()
    
    @Published private(set) var distance: Double = 0.0
    @Published private(set) var direction: simd_float3?
    @Published var isAvailable: Bool = false
    
    private(set) var session: NISession?
    private weak var parentManager: ProximityManager?
    
    // 用于 Token 交换的本机 Token
    private(set) var myDiscoveryToken: NIDiscoveryToken?
    
    override init() {
        super.init()
        checkAvailability()
    }
    
    private func checkAvailability() {
        isAvailable = NISession.isSupported
        if !isAvailable {
            print("[UWB] Device does not support Nearby Interaction")
        }
    }
    
    func configure(with manager: ProximityManager) {
        self.parentManager = manager
    }
    
    func start() throws {
        guard isAvailable else {
            throw WalkieTalkieError.uwbUnavailable
        }
        
        // 创建 NISession 并设置委托
        session = NISession()
        session?.delegate = self
        
        // 存储本机 Token 用于后续交换
        // 注意：需要通过 NISession 的 discoveryToken 获取
        if let token = session?.discoveryToken {
            myDiscoveryToken = token
            print("[UWB] Local discovery token available")
        }
        
        print("[UWB] Session started")
    }
    
    /// 使用对端的 NIDiscoveryToken 配置会话（Token 交换的核心）
    /// - Parameter peerToken: 从对端接收的 NIDiscoveryToken
    func configureWithPeerToken(_ peerToken: NIDiscoveryToken) {
        guard let session = session else {
            print("[UWB] No active session to configure")
            return
        }
        
        // 检查是否有本机 Token
        guard let myToken = myDiscoveryToken ?? session.discoveryToken else {
            print("[UWB] No local discovery token available")
            return
        }
        
        // 创建 NINearbyPeerConfiguration
        // 这是启动 NI 会话的关键配置
        let peerConfig = NINearbyPeerConfiguration(peerToken: peerToken)
        
        // 使用配置更新会话
        session.run(peerConfig)
        
        print("[UWB] Session configured with peer token")
    }
    
    /// 仅使用本机 Token 启动会话（用于接收对端连接）
    func startWithLocalToken() {
        guard let session = session else {
            print("[UWB] No active session")
            return
        }
        
        // 如果没有对端 Token，只运行本机配置
        if let localToken = session.discoveryToken {
            myDiscoveryToken = localToken
            // 对于接收方，我们等待对端连接后配置
            print("[UWB] Session ready, waiting for peer configuration")
        }
    }
    
    func stop() {
        session?.invalidate()
        session = nil
        myDiscoveryToken = nil
        distance = 0.0
        print("[UWB] Session stopped")
    }
}

extension UWBProximityProvider: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        
        if let newDistance = object.distance {
            distance = Double(newDistance)
            parentManager?.updateDistance(distance)
        }
        
        direction = object.direction
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], 
                 reason: NINearbyObject.RemovalReason) {
        if reason == .peerEnded {
            distance = 0.0
            parentManager?.updateDistance(0)
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("[UWB] Session invalidated: \(error)")
        isAvailable = false
    }
}

// MARK: - 蓝牙 Provider（降级方案）
class BluetoothProximityProvider: NSObject, ProximityProvider {
    static let shared = BluetoothProximityProvider()
    
    @Published private(set) var distance: Double = 0.0
    @Published private(set) var isAvailable: Bool = true
    @Published private(set) var rssi: Int = -50
    
    private weak var parentManager: ProximityManager?
    private var rssiTimer: Timer?
    
    // RSSI 到距离的映射（粗略估计）
    // 实际需要根据设备校准
    private func rssiToDistance(_ rssi: Int) -> Double {
        // 典型值: -30dBm = 1m, -70dBm = 5m, -90dBm = 20m+
        let measuredPower = -50 // 1米处的参考 RSSI
        let pathLossExponent = 2.0 // 自由空间路径损耗指数
        
        if rssi >= 0 {
            return 0.0
        }
        
        let distance = pow(10, Double(measuredPower - rssi) / (10 * pathLossExponent))
        return min(distance, 30.0) // 最大30米
    }
    
    func configure(with manager: ProximityManager) {
        self.parentManager = manager
    }
    
    func start() throws {
        print("[Bluetooth] Starting as fallback provider")
        
        // 启动模拟距离更新（实际项目中应该从 MultipeerConnectivity 获取 RSSI）
        // 这里使用模拟值，因为 MultipeerConnectivity 不直接提供 RSSI
        startRSSIMonitoring()
        
        isAvailable = true
    }
    
    private func startRSSIMonitoring() {
        // 模拟 RSSI 变化（在实际项目中替换为真实蓝牙 RSSI 读取）
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 模拟随机 RSSI 值（-50 到 -80 之间）
            // 在真实场景中，应该从 CBCentralManager 或 MCBrowserViewController 获取
            let simulatedRSSI = Int.random(in: -80 ... -50)
            self.rssi = simulatedRSSI
            
            // 转换为距离
            let newDistance = self.rssiToDistance(simulatedRSSI)
            self.distance = newDistance
            self.parentManager?.updateDistance(newDistance)
            
            print("[Bluetooth] RSSI: \(simulatedRSSI) dBm -> Distance: \(String(format: "%.2f", newDistance))m")
        }
    }
    
    func stop() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        distance = 0.0
        rssi = -50
        print("[Bluetooth] Stopped")
    }
}

// MARK: - 主控制器
class ProximityManager: ObservableObject {
    static let shared = ProximityManager()
    
    // MARK: - Published 属性
    @Published var currentDistance: Double = 0.0
    @Published var currentVolume: Float = 0.5
    @Published var state: WalkieState = .idle
    @Published var distanceLevel: DistanceLevel = .unknown
    @Published var connectedDevices: [String] = []
    @Published var tokenExchangeCompleted: Bool = false
    @Published var providerType: ProviderType = .bluetooth
    @Published var uwbAvailable: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - 多设备支持
    @Published private(set) var activeDevices: [TrackedDevice] = []
    @Published private(set) var discoverableDevices: [TrackedDevice] = []
    
    /// 当前距离（第一个活跃设备的距离，用于兼容旧UI）
    var currentPrimaryDistance: Double {
        activeDevices.first?.distance ?? 0.0
    }
    
    // MARK: - 内部组件
    private let uwbProvider = UWBProximityProvider.shared
    private let bluetoothProvider = BluetoothProximityProvider.shared
    private let audioController = AudioController()
    private var distanceSmoothers: [String: DistanceSmoother] = [:]
    private let peerManager = PeerManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var currentPeerID: MCPeerID?
    private var activeProvider: ProximityProvider?
    
    // MARK: - 配置
    var minDistance: Double = 1.0
    var maxDistance: Double = 10.0
    var minVolume: Float = 0.1
    var maxVolume: Float = 1.0
    var smoothingEnabled: Bool = true
    
    private init() {
        uwbProvider.configure(with: self)
        bluetoothProvider.configure(with: self)
        setupBindings()
        setupPeerManagerIntegration()
        
        // 检查 UWB 可用性
        uwbAvailable = uwbProvider.isAvailable
        if !uwbAvailable {
            print("[Manager] UWB not available, will use Bluetooth fallback")
        }
    }
    
    private func setupBindings() {
        // 监听 UWB 距离变化
        uwbProvider.$distance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] distance in
                guard self?.providerType == .uwb else { return }
                self?.updateDistance(distance)
            }
            .store(in: &cancellables)
        
        // 监听蓝牙距离变化
        bluetoothProvider.$distance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] distance in
                guard self?.providerType == .bluetooth else { return }
                self?.updateDistance(distance)
            }
            .store(in: &cancellables)
    }
    
    /// 设置与 PeerManager 的集成
    private func setupPeerManagerIntegration() {
        // 设置 Token 交换委托
        peerManager.tokenExchangeDelegate = self
        
        // 监听 PeerManager 连接状态变化
        peerManager.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self = self else { return }
                
                // 更新设备名称列表（保持兼容）
                self.connectedDevices = devices.map { $0.displayName }
                
                // 更新 TrackedDevice 列表
                for peerDevice in devices {
                    // 检查是否已存在
                    if self.activeDevices.contains(where: { $0.id == peerDevice.id }) {
                        continue
                    }
                    
                    // 创建新的 TrackedDevice
                    let tracked = TrackedDevice(peerID: peerDevice.peerID)
                    tracked.connectionState = .connected
                    
                    // 根据 UWB 可用性设置测距方式
                    if self.uwbAvailable {
                        tracked.providerType = .uwb
                    } else {
                        tracked.providerType = .bluetooth
                    }
                    
                    self.activeDevices.append(tracked)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 启动对讲功能
    func startWalkieTalkie() {
        guard state == .idle || state == .error else {
            print("[Manager] Already running")
            return
        }
        
        // 清除之前的错误
        errorMessage = nil
        
        transition(to: .discovering)
        
        // 配置音频
        do {
            try audioController.configureAudioSession()
        } catch {
            print("[Manager] Audio configuration failed: \(error)")
            errorMessage = "音频配置失败: \(error.localizedDescription)"
            transition(to: .error)
            return
        }
        
        // 启动 PeerManager（MultipeerConnectivity）
        peerManager.start()
        
        // 尝试启动 UWB，如果不可用则降级到蓝牙
        if uwbProvider.isAvailable {
            do {
                try uwbProvider.start()
                providerType = .uwb
                print("[Manager] Using UWB provider")
                transition(to: .connected)
            } catch {
                print("[Manager] UWB start failed, falling back to Bluetooth: \(error)")
                startBluetoothFallback()
            }
        } else {
            // UWB 不可用，直接使用蓝牙降级方案
            print("[Manager] UWB not available, using Bluetooth fallback")
            startBluetoothFallback()
        }
    }
    
    /// 启动蓝牙降级方案
    private func startBluetoothFallback() {
        do {
            try bluetoothProvider.start()
            providerType = .bluetooth
            errorMessage = "您的设备不支持 UWB，已切换到蓝牙模式（距离测量精度较低）"
            transition(to: .connected)
        } catch {
            print("[Manager] Bluetooth fallback failed: \(error)")
            errorMessage = "无法启动任何proximity provider: \(error.localizedDescription)"
            transition(to: .error)
        }
    }
    
    /// 停止对讲功能
    func stopWalkieTalkie() {
        uwbProvider.stop()
        bluetoothProvider.stop()
        peerManager.stop()
        
        // 重置所有设备的距离平滑器
        for smoother in distanceSmoothers.values {
            smoother.reset()
        }
        distanceSmoothers.removeAll()
        
        // 清空设备列表
        activeDevices.removeAll()
        discoverableDevices.removeAll()
        
        currentDistance = 0.0
        currentVolume = 0.5
        tokenExchangeCompleted = false
        currentPeerID = nil
        errorMessage = nil
        transition(to: .idle)
    }
    
    /// 主动发起 Token 交换（当有对端连接时调用）
    func initiateTokenExchange(with peerID: MCPeerID) {
        guard let token = uwbProvider.myDiscoveryToken ?? uwbProvider.session?.discoveryToken else {
            print("[Manager] No local discovery token available for exchange")
            return
        }
        
        currentPeerID = peerID
        peerManager.sendDiscoveryToken(token, to: peerID)
        
        print("[Manager] Initiating token exchange with \(peerID.displayName)")
    }
    
    /// 使用对端 Token 配置 NI 会话（Token 交换的核心步骤）
    func configureNISession(withPeerToken peerToken: NIDiscoveryToken, fromPeer peerID: MCPeerID) {
        currentPeerID = peerID
        
        // 使用 NINearbyPeerConfiguration 配置会话
        uwbProvider.configureWithPeerToken(peerToken)
        
        tokenExchangeCompleted = true
        transition(to: .transmitting)
        
        print("[Manager] NI session configured with peer token from \(peerID.displayName)")
    }
    
    /// 更新距离（由 Provider 调用 - 兼容旧版）
    func updateDistance(_ distance: Double) {
        // 更新第一个活跃设备的距离
        if let firstDevice = activeDevices.first {
            updateDistance(for: firstDevice.id, distance: distance, provider: firstDevice.providerType)
        }
    }
    
    /// 更新指定设备的距离（多设备支持）
    func updateDistance(for deviceId: String, distance: Double, provider: ProviderType) {
        guard let device = activeDevices.first(where: { $0.id == deviceId }) else { return }
        
        // 获取或创建设备的距离平滑器
        if distanceSmoothers[deviceId] == nil {
            distanceSmoothers[deviceId] = DistanceSmoother()
        }
        
        let smoothedDistance = smoothingEnabled 
            ? distanceSmoothers[deviceId]!.addSample(distance) 
            : distance
        
        // 更新设备属性
        device.distance = smoothedDistance
        device.distanceLevel = DistanceLevel(distance: smoothedDistance)
        device.providerType = provider
        device.lastSeen = Date()
        
        // 计算音量
        let newVolume = audioController.calculateVolume(
            distance: smoothedDistance,
            minDistance: minDistance,
            maxDistance: maxDistance,
            minVolume: minVolume,
            maxVolume: maxVolume
        )
        device.volume = newVolume
        
        // 更新全局属性（保持兼容）
        currentDistance = smoothedDistance
        currentVolume = newVolume
        distanceLevel = DistanceLevel(distance: smoothedDistance)
    }
    
    // MARK: - 状态管理
    
    private func transition(to newState: WalkieState) {
        guard state != newState else { return }
        print("[State] \(state.rawValue) → \(newState.rawValue)")
        state = newState
    }
}

// MARK: - TokenExchangeDelegate
extension ProximityManager: TokenExchangeDelegate {
    /// 当从对端收到 NIDiscoveryToken 时调用
    func peerManager(_ peerManager: PeerManager, didReceiveDiscoveryToken token: NIDiscoveryToken, fromPeer peerID: MCPeerID) {
        print("[Manager] Received discovery token from \(peerID.displayName)")
        
        // 使用接收到的 Token 配置 NI 会话
        // 这是 Token 交换流程的关键步骤
        configureNISession(withPeerToken: token, fromPeer: peerID)
    }
    
    /// Token 交换完成时调用
    func peerManager(_ peerManager: PeerManager, didCompleteTokenExchangeWith peerID: MCPeerID) {
        print("[Manager] Token exchange completed with \(peerID.displayName)")
        tokenExchangeCompleted = true
        
        // 双方都已交换 Token，现在可以开始 UWB 测距
        if let myToken = uwbProvider.myDiscoveryToken ?? uwbProvider.session?.discoveryToken {
            // 如果还没有配置对端 Token，现在配置
            if !tokenExchangeCompleted {
                // 检查是否已有对端 Token
                // 这里可以根据需要实现自动配置
            }
        }
    }
}
