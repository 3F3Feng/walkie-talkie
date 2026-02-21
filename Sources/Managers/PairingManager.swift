import Foundation

/// Represents a paired device
public struct PairedDevice: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let pairedAt: Date
    public var lastConnected: Date?
    
    public init(id: String, name: String, pairedAt: Date = Date(), lastConnected: Date? = nil) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastConnected = lastConnected
    }
}

/// Manages device pairing operations
public final class PairingManager {
    
    // MARK: - Properties
    
    private let provider: BLEProviderProtocol
    private let storage: PairingStorage
    
    public weak var delegate: PairingDelegate?
    
    /// Currently pending pairing request
    public private(set) var pendingRequest: PairingRequestPayload?
    
    /// All paired devices
    public private(set) var pairedDevices: [PairedDevice] = []
    
    /// Whether we're currently in pairing mode
    public private(set) var isInPairingMode: Bool = false
    
    /// Callback when paired devices change
    public var onPairedDevicesUpdated: (([PairedDevice]) -> Void)?
    
    // MARK: - Initialization
    
    public init(provider: BLEProviderProtocol, storage: PairingStorage = UserDefaultsPairingStorage()) {
        self.provider = provider
        self.storage = storage
        self.pairedDevices = storage.loadPairedDevices()
        provider.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Enter pairing mode
    public func startPairingMode() {
        isInPairingMode = true
        delegate?.pairingDidEnterMode(self)
    }
    
    /// Exit pairing mode
    public func stopPairingMode() {
        isInPairingMode = false
        pendingRequest = nil
        delegate?.pairingDidExitMode(self)
    }
    
    /// Request pairing with a device
    public func requestPairing(with device: BLEDevice) {
        let request = PairingRequestPayload(
            deviceId: device.id,
            deviceName: device.name,
            timestamp: Date().timeIntervalSince1970
        )
        
        do {
            let encoder = JSONEncoder()
            let payload = try encoder.encode(request)
            let message = BLEMessage(type: .pairingRequest, payload: payload)
            try provider.sendMessage(message, to: device)
            
            // Wait for response
            delegate?.pairing(self, didSendRequestTo: device)
        } catch {
            delegate?.pairing(self, didFailWithError: .sendFailed(device: device, reason: error.localizedDescription))
        }
    }
    
    /// Accept incoming pairing request
    public func acceptPairing(_ request: PairingRequestPayload) {
        guard let device = findDevice(byId: request.deviceId) else { return }
        
        let paired = PairedDevice(id: request.deviceId, name: request.deviceName)
        addPairedDevice(paired)
        
        // Send acceptance
        sendPairingResponse(.pairingAccept, to: device)
        
        pendingRequest = nil
        delegate?.pairing(self, didPairWith: device)
    }
    
    /// Reject incoming pairing request
    public func rejectPairing(_ request: PairingRequestPayload) {
        guard let device = findDevice(byId: request.deviceId) else { return }
        
        sendPairingResponse(.pairingReject, to: device)
        
        pendingRequest = nil
        delegate?.pairing(self, didReject: device)
    }
    
    /// Unpair from a device
    public func unpair(with deviceId: String) {
        pairedDevices.removeAll { $0.id == deviceId }
        storage.savePairedDevices(pairedDevices)
        
        // Send disconnect notification
        if let device = findDevice(byId: deviceId) {
            let message = BLEMessage(type: .disconnect, payload: Data())
            try? provider.sendMessage(message, to: device)
        }
        
        onPairedDevicesUpdated?(pairedDevices)
        delegate?.pairing(self, didUnpairWith: deviceId)
    }
    
    /// Check if device is paired
    public func isPaired(deviceId: String) -> Bool {
        return pairedDevices.contains { $0.id == deviceId }
    }
    
    // MARK: - Private Methods
    
    private func addPairedDevice(_ device: PairedDevice) {
        pairedDevices.append(device)
        storage.savePairedDevices(pairedDevices)
        onPairedDevicesUpdated?(pairedDevices)
    }
    
    private func sendPairingResponse(_ type: BLEMessageType, to device: BLEDevice) {
        let response = PairingResponsePayload(accepted: type == .pairingAccept)
        do {
            let encoder = JSONEncoder()
            let payload = try encoder.encode(response)
            let message = BLEMessage(type: type, payload: payload)
            try provider.sendMessage(message, to: device)
        } catch {
            // Handle silently
        }
    }
    
    private func findDevice(byId id: String) -> BLEDevice? {
        return provider.discoveredDevices.first { $0.id == id } 
            ?? provider.connectedDevices.first { $0.id == id }
    }
}

// MARK: - BLEProviderDelegate

extension PairingManager: BLEProviderDelegate {
    
    public func provider(_ provider: BLEProviderProtocol, didDiscover device: BLEDevice) {
        // Pass through
    }
    
    public func provider(_ provider: BLEProviderProtocol, didUpdateRSSI rssi: Int, for deviceId: String) {
        // Pass through
    }
    
    public func provider(_ provider: BLEProviderProtocol, didReceive message: BLEMessage, from device: BLEDevice) {
        switch message.type {
        case .pairingRequest:
            handlePairingRequest(message, from: device)
        case .pairingAccept:
            handlePairingResponse(accepted: true, from: device)
        case .pairingReject:
            handlePairingResponse(accepted: false, from: device)
        default:
            break
        }
    }
    
    public func provider(_ provider: BLEProviderProtocol, didConnectTo device: BLEDevice) {
        delegate?.pairing(self, didConnectTo: device)
    }
    
    public func provider(_ provider: BLEProviderProtocol, didDisconnectFrom device: BLEDevice, error: Error?) {
        delegate?.pairing(self, didDisconnectFrom: device)
    }
    
    public func provider(_ provider: BLEProviderProtocol, didEncounterError error: BLEError) {
        delegate?.pairing(self, didFailWithError: error)
    }
    
    private func handlePairingRequest(_ message: BLEMessage, from device: BLEDevice) {
        do {
            let request: PairingRequestPayload = try message.decodedPayload()
            pendingRequest = request
            delegate?.pairing(self, didReceiveRequest: request, from: device)
        } catch {
            delegate?.pairing(self, didFailWithError: .decodingFailed)
        }
    }
    
    private func handlePairingResponse(accepted: Bool, from device: BLEDevice) {
        if accepted {
            let paired = PairedDevice(id: device.id, name: device.name)
            addPairedDevice(paired)
            delegate?.pairing(self, didPairWith: device)
        } else {
            delegate?.pairing(self, didReject: device)
        }
    }
}

// MARK: - Supporting Types

public struct PairingResponsePayload: Codable {
    public let accepted: Bool
}

public protocol PairingDelegate: AnyObject {
    func pairingDidEnterMode(_ manager: PairingManager)
    func pairingDidExitMode(_ manager: PairingManager)
    func pairing(_ manager: PairingManager, didReceiveRequest request: PairingRequestPayload, from device: BLEDevice)
    func pairing(_ manager: PairingManager, didSendRequestTo device: BLEDevice)
    func pairing(_ manager: PairingManager, didPairWith device: BLEDevice)
    func pairing(_ manager: PairingManager, didReject device: BLEDevice)
    func pairing(_ manager: PairingManager, didUnpairWith deviceId: String)
    func pairing(_ manager: PairingManager, didConnectTo device: BLEDevice)
    func pairing(_ manager: PairingManager, didDisconnectFrom device: BLEDevice)
    func pairing(_ manager: PairingManager, didFailWithError error: BLEError)
}

public extension PairingDelegate {
    func pairingDidEnterMode(_ manager: PairingManager) {}
    func pairingDidExitMode(_ manager: PairingManager) {}
    func pairing(_ manager: PairingManager, didReceiveRequest request: PairingRequestPayload, from device: BLEDevice) {}
    func pairing(_ manager: PairingManager, didSendRequestTo device: BLEDevice) {}
    func pairing(_ manager: PairingManager, didPairWith device: BLEDevice) {}
    func pairing(_ manager: PairingManager, didReject device: BLEDevice) {}
    func pairing(_ manager: PairingManager, didUnpairWith deviceId: String) {}
    func pairing(_ manager: PairingManager, didConnectTo device: BLEDevice) {}
    func pairing(_ manager: PairingManager, didDisconnectFrom device: BLEDevice) {}
    func pairing(_ manager: PairingManager, didFailWithError error: BLEError) {}
}

// MARK: - Storage Protocol

public protocol PairingStorage {
    func loadPairedDevices() -> [PairedDevice]
    func savePairedDevices(_ devices: [PairedDevice])
}

// MARK: - UserDefaults Storage

public final class UserDefaultsPairingStorage: PairingStorage {
    
    private let key = "walkie_talkie_paired_devices"
    
    public init() {}
    
    public func loadPairedDevices() -> [PairedDevice] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
    }
    
    public func savePairedDevices(_ devices: [PairedDevice]) {
        let data = try? JSONEncoder().encode(devices)
        UserDefaults.standard.set(data, forKey: key)
    }
}
