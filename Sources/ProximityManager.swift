import Foundation
import NearbyInteraction
import CoreBluetooth
import Combine
import AVFoundation
import simd
import MultipeerConnectivity
import UIKit

// MARK: - 协议定义
protocol ProximityProvider {
    var distance: Double { get }
    var isAvailable: Bool { get }
    func start() throws
    func stop()
}


// MARK: - Token Exchange 状态
enum TokenExchangeState: String {
    case idle = "空闲"
    case waiting = "等待对端Token"
    case received = "已接收对端Token"
    case completed = "Token交换完成"
}


// MARK: - Peer 消息类型
enum PeerMessageType: String, Codable {
    case handshake = "handshake"
    case heartbeat = "heartbeat"
    case volumeSync = "volumeSync"
    case disconnect = "disconnect"
    case discoveryToken = "discoveryToken"
    case tokenAck = "tokenAck"
    case audioStream = "audioStream"
    case pairingRequest = "pairingRequest"
    case pairingAccept = "pairingAccept"
    case pairingReject = "pairingReject"
    case deviceInfo = "deviceInfo"  // 交换设备信息
}


struct PeerMessage: Codable {
    let type: PeerMessageType
    let timestamp: TimeInterval
    let payload: [String: String]?
    
    init(type: PeerMessageType, payload: [String: String]? = nil) {
        self.type = type
        self.timestamp = Date().timeIntervalSince1970
        self.payload = payload
    }
}


// MARK: - 音频流消息

// MARK: - 设备信息消息
struct DeviceInfoMessage: Codable {
    let deviceName: String
    let isWalkieTalkie: Bool
    let isInPairingMode: Bool
    let timestamp: TimeInterval
}

struct AudioStreamMessage: Codable {
    let sequenceNumber: UInt32
    let timestamp: TimeInterval
    let audioData: Data
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
    var displayName: String
    
    @Published var connectionState: DeviceConnectionState = .connecting
    @Published var distance: Double = 0.0
    @Published var distanceLevel: DistanceLevel = .unknown
    @Published var volume: Float = 0.5
    @Published var providerType: ProviderType = .bluetooth
    @Published var rssi: Int = -50
    @Published var lastSeen: Date = Date()
    @Published var isSelected: Bool = false
    @Published var pairingState: PairingState = .none
    var isWalkieTalkie: Bool = false  // 是否为 WalkieTalkie 设备
    
    // UWB Token（用于 UWB 测距）
    var niToken: NIDiscoveryToken?
    
    init(peerID: MCPeerID) {
        self.id = peerID.displayName
        self.peerID = peerID
        self.displayName = peerID.displayName
    }
    
    // 从已配对设备恢复的初始化器
    init(displayName: String) {
        self.id = displayName
        self.peerID = MCPeerID(displayName: displayName)
        self.displayName = displayName
        self.connectionState = .connected
        self.pairingState = .paired
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
            self.parentManager?.updateDistance(newDistance, deviceId: nil)
            
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
class ProximityManager: NSObject, ObservableObject {
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
    @Published var isPairingMode: Bool = false
    @Published var appMode: AppMode = .talk
    @Published var talkMode: TalkMode = .auto
    @Published private(set) var pairedDevices: [TrackedDevice] = []
    @Published var pendingPairingRequest: TrackedDevice? = nil
    
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
    
    // MARK: - MultipeerConnectivity (从 PeerManager 迁移)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let myPeerID: MCPeerID
    private let serviceType = "walkie-talkie"
    
    // MARK: - 音频流 (从 PeerManager 迁移)
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var audioSequenceNumber: UInt32 = 0
    @Published var isRecording = false
    @Published var isPlaying = false
    
    // MARK: - Token 交换状态
    private var receivedTokens: [String: Data] = [:]
    private var tokenExchangeTimeout: Timer?
    @Published var tokenExchangeState: TokenExchangeState = .idle
    
    private var cancellables = Set<AnyCancellable>()
    private var currentPeerID: MCPeerID?
    private var activeProvider: ProximityProvider?
    
    // MARK: - 配置
    var minDistance: Double = 1.0
    var maxDistance: Double = 10.0
    var minVolume: Float = 0.1
    var maxVolume: Float = 1.0
    var smoothingEnabled: Bool = true
    
    private override init() {
        // 初始化本机 PeerID (必须在 super.init() 之前)
        let deviceName = UIDevice.current.name
        myPeerID = MCPeerID(displayName: deviceName)
        
        super.init()
        
        uwbProvider.configure(with: self)
        bluetoothProvider.configure(with: self)
        setupBindings()
        
        // 检查 UWB 可用性
        uwbAvailable = uwbProvider.isAvailable
        if !uwbAvailable {
            print("[Manager] UWB not available, will use Bluetooth fallback")
        }
        
        print("[Manager] Initialized: \(deviceName)")
    }
    
    // MARK: - MCSession 管理 (从 PeerManager 迁移)
    
    private func startMultipeerSession() {
        guard session == nil else { return }
        
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // 开始广播和发现
        startAdvertising()
        startBrowsing()
        
        print("[Manager] Multipeer session started")
    }
    
    private func stopMultipeerSession() {
        stopAdvertising()
        stopBrowsing()
        session?.disconnect()
        session = nil
        discoveredPeers.removeAll()
        print("[Manager] Multipeer session stopped")
    }
    
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    
    private func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["version": "1.0"], serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        print("[Manager] Started advertising")
    }
    
    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }
    
    private func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        print("[Manager] Started browsing")
    }
    
    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }
    
    // MARK: - 音频流方法 (从 PeerManager 迁移)
    
    private func setupAudioEngine() throws {
        guard audioEngine == nil else { return }
        
        try audioController.configureAudioSession()
        
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: true)
        
        audioPlayer = AVAudioPlayerNode()
        engine.attach(audioPlayer!)
        
        if let player = audioPlayer, let format = audioFormat {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        
        try engine.start()
        print("[Manager] Audio engine started")
    }
    
    private func stopAudioEngine() {
        audioEngine?.stop()
        audioEngine = nil
        audioPlayer = nil
    }
    
    /// 开始 PTT 通话
    func startPTT() {
        guard let session = session, !session.connectedPeers.isEmpty else {
            print("[Manager] No peers connected for PTT")
            return
        }
        
        do {
            try setupAudioEngine()
            
            audioEngine?.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                self?.sendAudioBuffer(buffer)
            }
            
            audioPlayer?.play()
            isRecording = true
            print("[Manager] PTT started")
        } catch {
            print("[Manager] PTT start failed: \(error)")
        }
    }
    
    /// 停止 PTT 通话
    func stopPTT() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        print("[Manager] PTT stopped")
    }
    
    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let session = session, !session.connectedPeers.isEmpty,
              let channelData = buffer.int16ChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let audioData = Data(bytes: channelData[0], count: frameLength * 2)
        
        let streamMsg = AudioStreamMessage(sequenceNumber: audioSequenceNumber, timestamp: Date().timeIntervalSince1970, audioData: audioData)
        
        do {
            let data = try JSONEncoder().encode(streamMsg)
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
            audioSequenceNumber += 1
        } catch {
            // 静默失败
        }
    }
    
    private func handleReceivedAudio(_ data: Data) {
        guard let streamMsg = try? JSONDecoder().decode(AudioStreamMessage.self, from: data) else { return }
        
        guard let player = audioPlayer, let format = audioFormat else { return }
        
        do {
            let audioBuffer = try AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(streamMsg.audioData.count / 2))
            streamMsg.audioData.withUnsafeBytes { rawBufferPointer in
                if let baseAddress = rawBufferPointer.baseAddress {
                    let int16Pointer = baseAddress.assumingMemoryBound(to: Int16.self)
                    let frameCount = AVAudioFrameCount(streamMsg.audioData.count / 2)
                    audioBuffer?.frameLength = frameCount
                    audioBuffer?.int16ChannelData?[0].update(from: int16Pointer, count: Int(frameCount))
                }
            }
            
            if let buffer = audioBuffer {
                player.scheduleBuffer(buffer, completionHandler: nil)
            }
            
            if !player.isPlaying {
                player.play()
            }
            
            isPlaying = true
        } catch {
            print("[Manager] Audio playback error: \(error)")
        }
    }
    
    // MARK: - Token 交换方法 (从 PeerManager 迁移)
    
    private func sendDiscoveryToken(_ token: NIDiscoveryToken, to peerID: MCPeerID) {
        guard let session = session else { return }
        
        do {
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            let base64Token = tokenData.base64EncodedString()
            let message = PeerMessage(type: .discoveryToken, payload: ["token": base64Token, "sender": myPeerID.displayName])
            
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: [peerID], with: .reliable)
            
            tokenExchangeState = .waiting
            startTokenExchangeTimer()
            print("[Manager] DiscoveryToken sent to \(peerID.displayName)")
        } catch {
            print("[Manager] Failed to send token: \(error)")
            tokenExchangeState = .idle
        }
    }
    
    private func handleReceivedToken(_ message: PeerMessage, from peerID: MCPeerID) {
        guard let payload = message.payload, let base64Token = payload["token"],
              let tokenData = Data(base64Encoded: base64Token),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            print("[Manager] Invalid token received")
            return
        }
        
        receivedTokens[peerID.displayName] = tokenData
        tokenExchangeState = .received
        
        // 触发 Token 交换
        if let myToken = uwbProvider.myDiscoveryToken ?? uwbProvider.session?.discoveryToken {
            configureNISession(withPeerToken: token, fromPeer: peerID)
            sendTokenAck(to: peerID)
        }
        
        print("[Manager] Received token from \(peerID.displayName)")
    }
    
    private func sendTokenAck(to peerID: MCPeerID) {
        let ack = PeerMessage(type: .tokenAck, payload: ["ack": "true"])
        send(message: ack, to: [peerID])
        
        if tokenExchangeState == .received {
            tokenExchangeState = .completed
            invalidateTokenExchangeTimer()
        }
    }
    
    private func startTokenExchangeTimer() {
        tokenExchangeTimeout?.invalidate()
        tokenExchangeTimeout = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.tokenExchangeState = .idle
        }
    }
    
    private func invalidateTokenExchangeTimer() {
        tokenExchangeTimeout?.invalidate()
        tokenExchangeTimeout = nil
    }
    
    private func send(message: PeerMessage, to peers: [MCPeerID]? = nil) {
        guard let session = session else { return }
        do {
            let data = try JSONEncoder().encode(message)
            let targets = peers ?? session.connectedPeers
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            print("[Manager] Send failed: \(error)")
        }
    }
    
    private func initiateAutomaticTokenExchange(with peerID: MCPeerID) {
        guard let myToken = uwbProvider.myDiscoveryToken ?? uwbProvider.session?.discoveryToken else {
            print("[Manager] No local token for exchange")
            return
        }
        sendDiscoveryToken(myToken, to: peerID)
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
        
        // 启动 MultipeerConnectivity 会话
        startMultipeerSession()
        
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
        stopMultipeerSession()
        stopAudioEngine()
        
        // 重置所有设备的距离平滑器
        for smoother in distanceSmoothers.values {
            smoother.reset()
        }
        distanceSmoothers.removeAll()
        
        // 清空设备列表 - 保留已配对设备
        discoverableDevices.removeAll()
        
        // 保留已配对设备的连接
        let pairedIds = Set(pairedDevices.map { $0.id })
        activeDevices.removeAll { !pairedIds.contains($0.id) }
        
        // 重置已配对设备状态
        for device in pairedDevices {
            device.distance = 0.0
            device.distanceLevel = .unknown
            device.volume = 0.5
            device.connectionState = .disconnected
            device.providerType = .bluetooth
        }
        
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
        sendDiscoveryToken(token, to: peerID)
        
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
    func updateDistance(_ distance: Double, deviceId: String? = nil) {
        // 如果指定了设备ID，使用它；否则使用第一个活跃设备
        let targetId = deviceId ?? activeDevices.first?.id
        guard let targetDeviceId = targetId else {
            print("[Distance] ⚠️ 无设备可更新距离: \(String(format: "%.2f", distance))m")
            return
        }
        
        // 确定 Provider 类型
        let provider: ProviderType = uwbAvailable ? .uwb : .bluetooth
        updateDistance(for: targetDeviceId, distance: distance, provider: provider)
        
        print("[Distance] 📍 \(targetDeviceId): \(String(format: "%.2f", distance))m [\(provider.rawValue)]")
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
    
    // MARK: - 配对功能
    
    /// 切换配对模式（异步版 - 避免 UI 卡顿）
    func addDiscoveredDevice(_ device: TrackedDevice) {
        if !discoverableDevices.contains(where: { $0.id == device.id }) {
            discoverableDevices.append(device)
        }
    }
    
    func togglePairingMode() {
        isPairingMode.toggle()
        print("[Manager] Pairing mode: \(isPairingMode ? "ON" : "OFF")")
        
        if isPairingMode {
            appMode = .pairing
            // 双模搜索：UWB + BLE
            startMultipeerSession()
            BLEDiscoveryProvider.shared.configure(with: self)
            BLEDiscoveryProvider.shared.start()
            transition(to: .discovering)
        } else {
            appMode = .talk
            stopMultipeerSession()
            BLEDiscoveryProvider.shared.stop()
            transition(to: .idle)
        }
    }
    
    private func cleanupUnpairedDevices() {
        let pairedIds = Set(pairedDevices.map { $0.id })
        
        // 保留已配对设备
        activeDevices.removeAll { device in
            !pairedIds.contains(device.id)
        }
        
        // 保留已配对或已连接的可发现设备
        discoverableDevices.removeAll { device in
            !pairedIds.contains(device.id) && device.connectionState != .connected
        }
        
        print("[Manager] Cleaned up - Active: \(activeDevices.count), Paired: \(pairedDevices.count)")
    }
    
    /// 请求配对
    func requestPairing(with device: TrackedDevice) {
        device.pairingState = .pending
        print("[Manager] Requesting pairing with: \(device.displayName)")
        
        let message = PeerMessage(type: .pairingRequest, payload: ["deviceName": myPeerID.displayName])
        send(message: message, to: [device.peerID])
        
        // 30秒超时
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if device.pairingState == .pending {
                device.pairingState = .none
            }
        }
    }
    
    /// 接受配对
    func acceptPairing(with device: TrackedDevice) {
        device.pairingState = .paired
        device.connectionState = .connected
        savePairedDevice(device)
        
        let message = PeerMessage(type: .pairingAccept, payload: ["deviceName": myPeerID.displayName])
        send(message: message, to: [device.peerID])
        
        pendingPairingRequest = nil
        print("[Manager] ✅ Paired with: \(device.displayName)")
    }
    
    /// 拒绝配对
    func rejectPairing(with device: TrackedDevice) {
        device.pairingState = .none
        
        let message = PeerMessage(type: .pairingReject, payload: ["deviceName": myPeerID.displayName])
        send(message: message, to: [device.peerID])
        
        pendingPairingRequest = nil
    }
    
    /// 切换设备选中状态
    func toggleDeviceSelection(_ device: TrackedDevice) {
        for d in pairedDevices { d.isSelected = false }
        for d in activeDevices { d.isSelected = false }
        for d in discoverableDevices { d.isSelected = false }
        device.isSelected.toggle()
    }
    
    /// 保存已配对设备
    private func savePairedDevice(_ device: TrackedDevice) {
        var names = UserDefaults.standard.stringArray(forKey: "pairedDeviceNames") ?? []
        if !names.contains(device.displayName) {
            names.append(device.displayName)
            UserDefaults.standard.set(names, forKey: "pairedDeviceNames")
        }
        if !pairedDevices.contains(where: { $0.id == device.id }) {
            pairedDevices.append(device)
        }
    }
    
    /// 加载已配对设备
    func loadPairedDevices() {
        let names = UserDefaults.standard.stringArray(forKey: "pairedDeviceNames") ?? []
        pairedDevices = names.map { TrackedDevice(displayName: $0) }
        print("[Manager] Loaded \(pairedDevices.count) paired devices")
    }
    
    /// 处理配对请求消息
    private func handlePairingRequest(_ message: PeerMessage, from peerID: MCPeerID) {
        guard let deviceName = message.payload?["deviceName"] else { return }
        print("[Manager] Pairing request from: \(deviceName)")
        
        let device: TrackedDevice
        if let existing = activeDevices.first(where: { $0.id == peerID.displayName }) {
            device = existing
        } else {
            device = TrackedDevice(peerID: peerID)
            activeDevices.append(device)
        }
        device.pairingState = .pending
        
        DispatchQueue.main.async { [weak self] in
            self?.pendingPairingRequest = device
        }
    }
    
    /// 处理配对接受消息
    private func handlePairingAccept(_ message: PeerMessage, from peerID: MCPeerID) {
        guard let deviceName = message.payload?["deviceName"] else { return }
        print("[Manager] ✅ Pairing accepted by: \(deviceName)")
        
        if let device = activeDevices.first(where: { $0.id == peerID.displayName }) {
            device.pairingState = .paired
            device.connectionState = .connected
            savePairedDevice(device)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.pendingPairingRequest = nil
        }
    }
    
    /// 处理配对拒绝消息
    private func handlePairingReject(_ message: PeerMessage, from peerID: MCPeerID) {
        guard let deviceName = message.payload?["deviceName"] else { return }
        print("[Manager] Pairing rejected by: \(deviceName)")
        
        if let device = activeDevices.first(where: { $0.id == peerID.displayName }) {
            device.pairingState = .none
        }
    }

    /// 处理设备信息消息
    private func handleDeviceInfo(_ message: PeerMessage, from peerID: MCPeerID) {
        guard let payload = message.payload,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let info = try? JSONDecoder().decode(DeviceInfoMessage.self, from: data) else { return }
        
        print("[Manager] 📱 收到设备信息: \(info.deviceName), WalkieTalkie: \(info.isWalkieTalkie), 配对模式: \(info.isInPairingMode)")
        
        // 更新设备信息
        if let device = activeDevices.first(where: { $0.id == peerID.displayName }) {
            device.displayName = info.deviceName
            device.isWalkieTalkie = info.isWalkieTalkie
            device.connectionState = .connected
        }
        if let device = discoverableDevices.first(where: { $0.id == peerID.displayName }) {
            device.displayName = info.deviceName
            device.isWalkieTalkie = info.isWalkieTalkie
            device.connectionState = .connected
        }
    }

    /// 发送设备信息给已连接设备
    func sendDeviceInfo(to peerID: MCPeerID) {
        let info = DeviceInfoMessage(
            deviceName: myPeerID.displayName,
            isWalkieTalkie: true,
            isInPairingMode: isPairingMode,
            timestamp: Date().timeIntervalSince1970
        )
        
        if let data = try? JSONEncoder().encode(info),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = PeerMessage(type: .deviceInfo, payload: payload.mapValues { "\($0)" })
            send(message: message, to: [peerID])
            print("[Manager] 📤 已发送设备信息给: \(peerID.displayName)")
        }
    }}


// MARK: - MCSessionDelegate
extension ProximityManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            print("[Session] 📱 设备 \(peerID.displayName) 状态变化: \(state.rawValue)")
            
            switch state {
            case .connecting:
                print("[Session] ⏳ 正在连接: \(peerID.displayName)")
                
            case .connected:
                print("[Session] ✅ 已连接: \(peerID.displayName)")
                // 连接成功后发送设备信息
                self.sendDeviceInfo(to: peerID)
                
                let tracked = TrackedDevice(peerID: peerID)
                tracked.connectionState = .connected
                tracked.providerType = self.uwbAvailable ? .uwb : .bluetooth
                
                // 先添加到可发现设备（如果不在的话）
                if !self.discoverableDevices.contains(where: { $0.id == peerID.displayName }) {
                    self.discoverableDevices.append(tracked)
                }
                
                // 移动到已连接设备
                self.activeDevices.append(tracked)
                self.discoverableDevices.removeAll { $0.id == peerID.displayName }
                
                print("[Session] 📋 已连接设备: \(self.activeDevices.count), 可发现设备: \(self.discoverableDevices.count)")
                
                // 自动触发 Token 交换
                self.initiateAutomaticTokenExchange(with: peerID)
                
            case .notConnected:
                print("[Session] 🔌 已断开: \(peerID.displayName)")
                self.activeDevices.removeAll { $0.id == peerID.displayName }
                self.discoverableDevices.removeAll { $0.id == peerID.displayName }
                self.receivedTokens.removeValue(forKey: peerID.displayName)
                self.tokenExchangeState = .idle
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let message = try? JSONDecoder().decode(PeerMessage.self, from: data) {
            switch message.type {
            case .discoveryToken:
                handleReceivedToken(message, from: peerID)
            case .tokenAck:
                if tokenExchangeState == .waiting {
                    tokenExchangeState = .completed
                    invalidateTokenExchangeTimer()
                }
            case .audioStream:
                handleReceivedAudio(data)
            case .pairingRequest:
                handlePairingRequest(message, from: peerID)
            case .pairingAccept:
                handlePairingAccept(message, from: peerID)
            case .pairingReject:
                handlePairingReject(message, from: peerID)
            case .deviceInfo:
                handleDeviceInfo(message, from: peerID)
            default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}


// MARK: - MCNearbyServiceAdvertiserDelegate
extension ProximityManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}


// MARK: - MCNearbyServiceBrowserDelegate
extension ProximityManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("[Browser] 🔍 发现设备: \(peerID.displayName)")
        
        if !discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
            discoveredPeers.append(peerID)
            
            // 添加到可发现设备列表
            let tracked = TrackedDevice(peerID: peerID)
            tracked.connectionState = .connecting
            discoverableDevices.append(tracked)
            
            print("[Browser] ➕ 已添加到可发现设备: \(peerID.displayName), 当前: \(discoverableDevices.count) 个")
            
            // 自动邀请连接
            browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
            print("[Browser] 📤 已发送连接邀请给: \(peerID.displayName)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[Browser] ❌ 丢失设备: \(peerID.displayName)")
        discoveredPeers.removeAll { $0.displayName == peerID.displayName }
        discoverableDevices.removeAll { $0.id == peerID.displayName }
    }
}


// MARK: - 配对状态
enum PairingState: String {
    case none = "未配对"
    case pending = "等待确认"
    case paired = "已配对"
}


// MARK: - 应用模式（配对 vs 对话）
enum AppMode: String {
    case pairing = "配对模式"
    case talk = "对话模式"
}


// MARK: - 对话模式（自动 vs PTT）
enum TalkMode: String {
    case auto = "自动"
    case ptt = "按键说话"
}


// MARK: - CoreBluetooth 真实 BLE 扫描
class BLEDiscoveryProvider: NSObject, CBCentralManagerDelegate {
    static let shared = BLEDiscoveryProvider()
    
    private var centralManager: CBCentralManager?
    private weak var parentManager: ProximityManager?
    
    @Published private(set) var isAvailable: Bool = false
    
    func configure(with manager: ProximityManager) {
        self.parentManager = manager
    }
    
    func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func stop() {
        centralManager?.stopScan()
        centralManager = nil
        isAvailable = false
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[BLE] 状态: \(central.state.rawValue)")
        if central.state == .poweredOn {
            isAvailable = true
            central.scanForPeripherals(withServices: nil, options: nil)
            print("[BLE] 🔍 开始扫描")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue > -90 else { return }
        
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "BLE设备"
        let distance = rssiToDistance(RSSI.intValue)
        
        print("[BLE] 📱 \(name) RSSI:\(RSSI) dBm → \(String(format: "%.1f", distance))m")
        
        guard let parent = parentManager else { return }
        
        let deviceId = peripheral.identifier.uuidString
        if let existing = parent.discoverableDevices.first(where: { $0.id == deviceId }) {
            existing.distance = distance
            existing.rssi = RSSI.intValue
            existing.lastSeen = Date()
        } else {
            let device = TrackedDevice(bleName: name, bleId: deviceId)
            device.distance = distance
            device.rssi = RSSI.intValue
            device.providerType = .bluetooth
            device.connectionState = .connecting
            parent.addDiscoveredDevice(device)
            print("[BLE] ➕ 添加: \(name)")
        }
    }
    
    private func rssiToDistance(_ rssi: Int) -> Double {
        let power = -50
        if rssi >= 0 { return 0 }
        return min(pow(10, Double(power - rssi) / 20), 50)
    }
}


// MARK: - TrackedDevice BLE 初始化
extension TrackedDevice {
    convenience init(bleName: String, bleId: String) {
        let fakePeerID = MCPeerID(displayName: bleName)
        self.init(peerID: fakePeerID)
    }
}

