import Foundation
import CoreBluetooth

/// Represents a BLE device for discovery
public struct BLEDevice: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let uuid: UUID
    public var rssi: Int
    public var lastSeen: Date
    public var isConnected: Bool
    
    public init(
        id: String,
        name: String,
        uuid: UUID = UUID(),
        rssi: Int = -100,
        lastSeen: Date = Date(),
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.uuid = uuid
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.isConnected = isConnected
    }
    
    public static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Represents a message type for BLE communication
public enum BLEMessageType: String, Codable {
    case deviceInfo = "deviceInfo"
    case pairingRequest = "pairingRequest"
    case pairingAccept = "pairingAccept"
    case pairingReject = "pairingReject"
    case audioData = "audioData"
    case disconnect = "disconnect"
}

/// BLE message structure
public struct BLEMessage: Codable {
    public let type: BLEMessageType
    public let payload: Data
    public let timestamp: TimeInterval
    
    public init(type: BLEMessageType, payload: Data, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
    }
    
    /// Helper to decode JSON payload
    public func decodedPayload<T: Decodable>() throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: payload)
    }
}

/// Device info payload
public struct DeviceInfoPayload: Codable {
    public let displayName: String
    public let isInPairingMode: Bool
    public let isWalkieTalkie: Bool
    public let timestamp: TimeInterval
}

/// Pairing request payload
public struct PairingRequestPayload: Codable {
    public let deviceId: String
    public let deviceName: String
    public let timestamp: TimeInterval
    
    public init(deviceId: String, deviceName: String, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.timestamp = timestamp
    }
}

/// Audio data payload
public struct AudioDataPayload: Codable {
    public let chunks: Int
    public let totalSize: Int
    public let data: [UInt8]
}

// MARK: - BLE Provider Protocol

public protocol BLEProviderDelegate: AnyObject {
    func provider(_ provider: BLEProviderProtocol, didDiscover device: BLEDevice)
    func provider(_ provider: BLEProviderProtocol, didUpdateRSSI rssi: Int, for deviceId: String)
    func provider(_ provider: BLEProviderProtocol, didReceive message: BLEMessage, from device: BLEDevice)
    func provider(_ provider: BLEProviderProtocol, didConnectTo device: BLEDevice)
    func provider(_ provider: BLEProviderProtocol, didDisconnectFrom device: BLEDevice, error: Error?)
    func provider(_ provider: BLEProviderProtocol, didEncounterError error: BLEError)
}

public protocol BLEProviderProtocol: AnyObject {
    var delegate: BLEProviderDelegate? { get set }
    var isScanning: Bool { get }
    var isAdvertising: Bool { get }
    var discoveredDevices: [BLEDevice] { get }
    var connectedDevices: [BLEDevice] { get }
    
    /// Start scanning for BLE devices
    func startScanning()
    
    /// Stop scanning
    func stopScanning()
    
    /// Start advertising as a peripheral
    func startAdvertising(withName name: String)
    
    /// Stop advertising
    func stopAdvertising()
    
    /// Connect to a specific device
    func connect(to device: BLEDevice)
    
    /// Disconnect from a device
    func disconnect(from device: BLEDevice)
    
    /// Disconnect from all devices
    func disconnectAll()
    
    /// Send a message to a specific device
    func sendMessage(_ message: BLEMessage, to device: BLEDevice) throws
    
    /// Send message to all connected devices
    func broadcastMessage(_ message: BLEMessage) throws
    
    /// Clear discovered devices cache
    func clearDiscoveredDevices()
}

// MARK: - BLE Error Types

public enum BLEError: Error, LocalizedError {
    case notAuthorized
    case bluetoothPoweredOff
    case scanningFailed(reason: String)
    case advertisingFailed(reason: String)
    case connectionFailed(device: BLEDevice, reason: String)
    case sendFailed(device: BLEDevice, reason: String)
    case invalidState
    case deviceNotFound
    case serviceNotFound
    case characteristicNotFound
    case decodingFailed
    case encodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Bluetooth not authorized"
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off"
        case .scanningFailed(let reason):
            return "Scanning failed: \(reason)"
        case .advertisingFailed(let reason):
            return "Advertising failed: \(reason)"
        case .connectionFailed(let device, let reason):
            return "Connection to \(device.name) failed: \(reason)"
        case .sendFailed(let device, let reason):
            return "Send to \(device.name) failed: \(reason)"
        case .invalidState:
            return "Invalid Bluetooth state"
        case .deviceNotFound:
            return "Device not found"
        case .serviceNotFound:
            return "BLE service not found"
        case .characteristicNotFound:
            return "BLE characteristic not found"
        case .decodingFailed:
            return "Failed to decode message"
        case .encodingFailed:
            return "Failed to encode message"
        }
    }
}

// MARK: - Default Implementations

extension BLEProviderProtocol {
    public var discoveredDevices: [BLEDevice] {
        return []
    }
    
    public var connectedDevices: [BLEDevice] {
        return []
    }
}
