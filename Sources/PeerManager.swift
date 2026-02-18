import Foundation
import MultipeerConnectivity
import NearbyInteraction  // 需要 NIDiscoveryToken
import UIKit
import Combine

// MARK: - 设备对等体模型
struct PeerDevice: Identifiable {
    let peerID: MCPeerID
    let displayName: String
    var connectionState: ConnectionState
    var lastSeen: Date
    var rssi: Int?
    var customInfo: [String: String]
    
    var id: String { peerID.displayName }
    
    enum ConnectionState: String {
        case connecting = "连接中"
        case connected = "已连接"
        case disconnected = "已断开"
        case notConnected = "未连接"
    }
}

// MARK: - 消息类型
enum PeerMessageType: String, Codable {
    case handshake = "handshake"
    case heartbeat = "heartbeat"
    case volumeSync = "volumeSync"
    case disconnect = "disconnect"
    case discoveryToken = "discoveryToken"     // 新增：NIDiscoveryToken 消息
    case tokenAck = "tokenAck"                // 新增：Token 确认
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

// MARK: - PeerManager
class PeerManager: NSObject, ObservableObject {
    static let shared = PeerManager()
    
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var connectedDevices: [PeerDevice] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var tokenExchangeState: TokenExchangeState = .idle
    
    // MARK: - Token Exchange 委托
    weak var tokenExchangeDelegate: TokenExchangeDelegate?
    
    // MARK: - 内部状态
    private var pendingToken: Data?  // 等待发送的 Token
    private var receivedTokens: [String: Data] = [:]  // 已接收的对端 Token [peerID: tokenData]
    private var tokenExchangeTimeout: Timer?

// MARK: - Token Exchange 相关定义
enum TokenExchangeState: String {
    case idle = "空闲"
    case waiting = "等待对端Token"
    case received = "已接收对端Token"
    case completed = "Token交换完成"
}

protocol TokenExchangeDelegate: AnyObject {
    /// 当从对端收到 NIDiscoveryToken 时调用
    func peerManager(_ peerManager: PeerManager, didReceiveDiscoveryToken token: NIDiscoveryToken, fromPeer peerID: MCPeerID)
    /// Token 交换完成
    func peerManager(_ peerManager: PeerManager, didCompleteTokenExchangeWith peerID: MCPeerID)
}
    
    private var session: MCSession?
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    
    private let serviceType = "walkie-talkie"
    private let myPeerID: MCPeerID
    private var retryAttempts: [String: Int] = [:]
    private let maxRetryAttempts = 3
    
    private override init() {
        let deviceName = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: deviceName)
        super.init()
        print("[Peer] Initialized: \(deviceName)")
    }
    
    // MARK: - Service Control
    
    func start() {
        guard session == nil else { return }
        
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        startAdvertising()
        startBrowsing()
        print("[Peer] Service started")
    }
    
    func stop() {
        stopAdvertising()
        stopBrowsing()
        session?.disconnect()
        session = nil
        discoveredPeers.removeAll()
        connectedDevices.removeAll()
        retryAttempts.removeAll()
        print("[Peer] Service stopped")
    }
    
    // MARK: - Advertising
    
    private func startAdvertising() {
        let advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["version": "1.0"],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        serviceAdvertiser = advertiser
        isAdvertising = true
    }
    
    private func stopAdvertising() {
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceAdvertiser = nil
        isAdvertising = false
    }
    
    // MARK: - Browsing
    
    private func startBrowsing() {
        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        serviceBrowser = browser
        isBrowsing = true
    }
    
    private func stopBrowsing() {
        serviceBrowser?.stopBrowsingForPeers()
        serviceBrowser = nil
        isBrowsing = false
    }
    
    // MARK: - Connection
    
    func invitePeer(_ peerID: MCPeerID) {
        guard let session = session else { return }
        serviceBrowser?.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        isConnecting = true
    }
    
    func disconnectPeer(_ peerID: MCPeerID) {
        connectedDevices.removeAll { $0.peerID == peerID }
    }
    
    // MARK: - Messaging
    
    func send(message: PeerMessage, to peers: [MCPeerID]? = nil) {
        guard let session = session else { return }
        do {
            let data = try JSONEncoder().encode(message)
            let targets = peers ?? session.connectedPeers
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            print("[Peer] Send failed: \(error)")
        }
    }
    
    func sendHeartbeat() {
        send(message: PeerMessage(type: .heartbeat))
    }
    
    func syncVolume(_ volume: Float, distance: Double) {
        let msg = PeerMessage(type: .volumeSync, payload: [
            "volume": "\(volume)",
            "distance": "\(distance)"
        ])
        send(message: msg)
    }
    
    // MARK: - NIDiscoveryToken Exchange
    
    /// 发送本地 NIDiscoveryToken 到指定对端
    /// - Parameters:
    ///   - token: 本地生成的 NIDiscoveryToken
    ///   - peerID: 目标对端
    func sendDiscoveryToken(_ token: NIDiscoveryToken, to peerID: MCPeerID) {
        guard let session = session else {
            print("[Peer] Cannot send token: no session")
            return
        }
        
        // 将 Token 编码为 Data
        do {
            // NIDiscoveryToken 使用 NSKeyedArchiver 编码
            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            
            // 创建包含 Token 的消息
            let base64Token = tokenData.base64EncodedString()
            let message = PeerMessage(
                type: .discoveryToken,
                payload: [
                    "token": base64Token,
                    "sender": myPeerID.displayName
                ]
            )
            
            // 发送消息
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: [peerID], with: .reliable)
            
            print("[Peer] DiscoveryToken sent to \(peerID.displayName)")
            
            // 更新状态为等待对端 Token
            tokenExchangeState = .waiting
            startTokenExchangeTimer()
            
        } catch {
            print("[Peer] Failed to send DiscoveryToken: \(error)")
            tokenExchangeState = .idle
            tokenExchangeDelegate?.peerManager(self, didCompleteTokenExchangeWith: peerID)
        }
    }
    
    /// 处理接收到的 NIDiscoveryToken
    private func handleReceivedDiscoveryToken(_ message: PeerMessage, from peerID: MCPeerID) {
        guard let payload = message.payload,
              let base64Token = payload["token"] else {
            print("[Peer] Invalid token message received")
            return
        }
        
        // 解码 Token
        guard let tokenData = Data(base64Encoded: base64Token) else {
            print("[Peer] Failed to decode token data")
            return
        }
        
        do {
            // 使用 NSKeyedUnarchiver 解码 NIDiscoveryToken
            guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
                print("[Peer] Failed to unarchive NIDiscoveryToken")
                return
            }
            
            print("[Peer] Received DiscoveryToken from \(peerID.displayName)")
            
            // 存储接收到的 Token
            receivedTokens[peerID.displayName] = tokenData
            tokenExchangeState = .received
            
            // 调用委托告知 Token 已接收
            tokenExchangeDelegate?.peerManager(self, didReceiveDiscoveryToken: token, fromPeer: peerID)
            
            // 发送确认
            sendTokenAck(to: peerID)
            
        } catch {
            print("[Peer] Failed to decode NIDiscoveryToken: \(error)")
        }
    }
    
    /// 发送 Token 确认消息
    private func sendTokenAck(to peerID: MCPeerID) {
        let ack = PeerMessage(type: .tokenAck, payload: ["ack": "true"])
        send(message: ack, to: [peerID])
        
        // 检查是否双方都已完成交换
        checkTokenExchangeCompletion(with: peerID)
    }
    
    /// 处理收到的 Token 确认
    private func handleTokenAck(from peerID: MCPeerID) {
        print("[Peer] Received Token ACK from \(peerID.displayName)")
        checkTokenExchangeCompletion(with: peerID)
    }
    
    /// 检查 Token 交换是否完成
    private func checkTokenExchangeCompletion(with peerID: MCPeerID) {
        // 如果已经发送过 Token且收到了对方的 Token，则交换完成
        if tokenExchangeState == .received {
            tokenExchangeState = .completed
            invalidateTokenExchangeTimer()
            tokenExchangeDelegate?.peerManager(self, didCompleteTokenExchangeWith: peerID)
        }
    }
    
    /// 启动 Token 交换超时计时器
    private func startTokenExchangeTimer() {
        invalidateTokenExchangeTimer()
        tokenExchangeTimeout = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[Peer] Token exchange timeout")
            self.tokenExchangeState = .idle
        }
    }
    
    /// 停止 Token 交换计时器
    private func invalidateTokenExchangeTimer() {
        tokenExchangeTimeout?.invalidate()
        tokenExchangeTimeout = nil
    }
    
    /// 重置 Token 交换状态（当连接断开时调用）
    private func resetTokenExchangeState(for peerID: String) {
        receivedTokens.removeValue(forKey: peerID)
        tokenExchangeState = .idle
        invalidateTokenExchangeTimer()
    }
}

// MARK: - MCSessionDelegate
extension PeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connecting:
                self.isConnecting = true
            case .connected:
                self.isConnecting = false
                let device = PeerDevice(
                    peerID: peerID,
                    displayName: peerID.displayName,
                    connectionState: .connected,
                    lastSeen: Date(),
                    rssi: nil,
                    customInfo: [:]
                )
                self.connectedDevices.append(device)
                self.send(message: PeerMessage(type: .handshake), to: [peerID])
            case .notConnected:
                self.isConnecting = false
                self.connectedDevices.removeAll { $0.peerID == peerID }
            @unknown default: break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let message = try? JSONDecoder().decode(PeerMessage.self, from: data) {
            print("[Peer] Received \(message.type.rawValue) from \(peerID.displayName)")
            
            // 处理 Token 相关消息
            switch message.type {
            case .discoveryToken:
                handleReceivedDiscoveryToken(message, from: peerID)
            case .tokenAck:
                handleTokenAck(from: peerID)
            default:
                // 其他消息类型可在代理中处理
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension PeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        if !discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
            discoveredPeers.append(peerID)
            invitePeer(peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        discoveredPeers.removeAll { $0.displayName == peerID.displayName }
    }
}
