import Foundation
import MultipeerConnectivity

// MARK: - Provider Type
public enum ProviderType: String, Codable {
    case bluetooth = "bluetooth"
    case multipeer = "multipeer"
    case uwb = "uwb"
}

// MARK: - Pairing State
public enum PairingState: String, Codable {
    case none = "none"
    case pending = "pending"
    case paired = "paired"
}

// MARK: - TrackedDevice
public class TrackedDevice: Identifiable, ObservableObject {
    public let id: String
    public let name: String
    
    @Published public var rssi: Int
    @Published public var distance: Double
    @Published public var pairingState: PairingState
    @Published public var providerType: ProviderType
    @Published public var lastSeen: Date
    @Published public var isConnected: Bool
    
    // MARK: - Initialization
    
    /// Initialize from MultipeerConnectivity peer
    public init(peerID: MCPeerID) {
        self.id = peerID.displayName
        self.name = peerID.displayName
        self.rssi = -100
        self.distance = 0
        self.pairingState = .none
        self.providerType = .multipeer
        self.lastSeen = Date()
        self.isConnected = false
    }
    
    /// Initialize from BLE device
    public init(bleName: String, bleId: String) {
        self.id = bleId
        self.name = bleName
        self.rssi = -100
        self.distance = 0
        self.pairingState = .none
        self.providerType = .bluetooth
        self.lastSeen = Date()
        self.isConnected = false
    }
    
    /// Initialize with full parameters
    public init(
        id: String,
        name: String,
        rssi: Int = -100,
        distance: Double = 0,
        pairingState: PairingState = .none,
        providerType: ProviderType = .bluetooth,
        lastSeen: Date = Date(),
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.distance = distance
        self.pairingState = pairingState
        self.providerType = providerType
        self.lastSeen = lastSeen
        self.isConnected = isConnected
    }
    
    /// Display name for UI
    public var displayName: String {
        return name.isEmpty ? "Unknown Device" : name
    }
    
    /// Check if device is a Walkie device
    public var isWalkieDevice: Bool {
        return name.lowercased().contains("walkie")
    }
    
    /// Compare by id only
    public static func == (lhs: TrackedDevice, rhs: TrackedDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - TrackedDevice Array Extension
extension Array where Element: TrackedDevice {
    /// Sort by distance (nearest first)
    public func sortedByDistance() -> [TrackedDevice] {
        return self.sorted { $0.distance < $1.distance }
    }
    
    /// Sort by signal strength (strongest first)
    public func sortedByRSSI() -> [TrackedDevice] {
        return self.sorted { $0.rssi > $1.rssi }
    }
    
    /// Filter Walkie devices only
    public func walkieOnly() -> [TrackedDevice] {
        return self.filter { $0.isWalkieDevice }
    }
}
