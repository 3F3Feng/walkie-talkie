import Foundation
import NearbyInteraction
import CoreBluetooth
import Combine
import AVFoundation
import simd

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

// MARK: - 应用状态
enum WalkieState: String {
    case idle = "空闲"
    case discovering = "发现中"
    case connected = "已连接"
    case transmitting = "对讲中"
    case error = "错误"
}

// MARK: - 错误定义
enum WalkieTalkieError: Error {
    case uwbUnavailable
    case bluetoothNotAuthorized
    case audioSessionFailure
    case deviceNotSupported
}

// MARK: - 音频控制器
class AudioController {
    private let audioSession = AVAudioSession.sharedInstance()
    private var currentVolume: Float = 0.5
    
    func configureAudioSession() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowAirPlay, .defaultToSpeaker]
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
    
    private var session: NISession?
    private weak var parentManager: ProximityManager?
    
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
        
        session = NISession()
        session?.delegate = self
        print("[UWB] Session started")
    }
    
    func stop() {
        session?.invalidate()
        session = nil
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

// MARK: - 主控制器
class ProximityManager: ObservableObject {
    static let shared = ProximityManager()
    
    // MARK: - Published 属性
    @Published var currentDistance: Double = 0.0
    @Published var currentVolume: Float = 0.5
    @Published var state: WalkieState = .idle
    @Published var distanceLevel: DistanceLevel = .unknown
    @Published var connectedDevices: [String] = []
    
    // MARK: - 内部组件
    private let uwbProvider = UWBProximityProvider.shared
    private let audioController = AudioController()
    private let distanceSmoother = DistanceSmoother()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 配置
    var minDistance: Double = 1.0
    var maxDistance: Double = 10.0
    var minVolume: Float = 0.1
    var maxVolume: Float = 1.0
    var smoothingEnabled: Bool = true
    
    private init() {
        uwbProvider.configure(with: self)
        setupBindings()
    }
    
    private func setupBindings() {
        // 监听 UWB 距离变化
        uwbProvider.$distance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] distance in
                self?.updateDistance(distance)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 启动对讲功能
    func startWalkieTalkie() {
        guard state == .idle else {
            print("[Manager] Already running")
            return
        }
        
        transition(to: .discovering)
        
        // 配置音频
        do {
            try audioController.configureAudioSession()
        } catch {
            print("[Manager] Audio configuration failed: \(error)")
            transition(to: .error)
            return
        }
        
        // 启动 UWB
        do {
            try uwbProvider.start()
            if uwbProvider.isAvailable {
                transition(to: .connected)
            }
        } catch {
            print("[Manager] UWB start failed: \(error)")
            transition(to: .error)
        }
    }
    
    /// 停止对讲功能
    func stopWalkieTalkie() {
        uwbProvider.stop()
        distanceSmoother.reset()
        currentDistance = 0.0
        currentVolume = 0.5
        transition(to: .idle)
    }
    
    /// 更新距离（由 Provider 调用）
    func updateDistance(_ distance: Double) {
        let smoothedDistance = smoothingEnabled 
            ? distanceSmoother.addSample(distance) 
            : distance
        
        currentDistance = smoothedDistance
        distanceLevel = DistanceLevel(distance: smoothedDistance)
        
        // 计算并应用音量
        let newVolume = audioController.calculateVolume(
            distance: smoothedDistance,
            minDistance: minDistance,
            maxDistance: maxDistance,
            minVolume: minVolume,
            maxVolume: maxVolume
        )
        currentVolume = newVolume
        audioController.applyVolume(newVolume)
    }
    
    // MARK: - 状态管理
    
    private func transition(to newState: WalkieState) {
        guard state != newState else { return }
        print("[State] \(state.rawValue) → \(newState.rawValue)")
        state = newState
    }
}
