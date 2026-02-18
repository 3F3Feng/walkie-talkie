import Foundation
import MultipeerConnectivity
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
