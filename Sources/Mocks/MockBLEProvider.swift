import Foundation


/// Mock implementation of BLEProviderProtocol for testing
public final class MockBLEProvider: BLEProviderProtocol {
    
    // MARK: - Properties
    
    public weak var delegate: BLEProviderDelegate?
    public private(set) var isScanning: Bool = false
    public private(set) var isAdvertising: Bool = false
    public private(set) var discoveredDevices: [BLEDevice] = []
    public private(set) var connectedDevices: [BLEDevice] = []
    
    // MARK: - Configuration
    
    /// Whether startDiscovery should immediately simulate finding devices
    public var shouldDiscoverDevices: Bool = true
    
    /// Delay before simulating discovery (in seconds)
    public var discoveryDelay: TimeInterval = 0.5
    
    /// Pre-configured devices to discover
    public var mockDevices: [BLEDevice] = []
    
    /// Whether connection should succeed
    public var shouldConnectionSucceed: Bool = true
    
    /// Whether send should succeed
    public var shouldSendSucceed: Bool = true
    
    /// Track all sent messages
    public private(set) var sentMessages: [(message: BLEMessage, device: BLEDevice)] = []
    
    // MARK: - Call Tracking
    
    public private(set) var startScanningCallCount: Int = 0
    public private(set) var stopScanningCallCount: Int = 0
    public private(set) var startAdvertisingCallCount: Int = 0
    public private(set) var stopAdvertisingCallCount: Int = 0
    public private(set) var connectCallCount: Int = 0
    public private(set) var disconnectCallCount: Int = 0
    public private(set) var sendMessageCallCount: Int = 0
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    public func startScanning() {
        startScanningCallCount += 1
        isScanning = true
        
        if shouldDiscoverDevices {
            // Simulate discovering devices after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDelay) { [weak self] in
                guard let self = self, self.isScanning else { return }
                
                let devices = self.mockDevices.isEmpty ? self.defaultMockDevices() : self.mockDevices
                for device in devices {
                    self.discoveredDevices.append(device)
                    self.delegate?.provider(self, didDiscover: device)
                }
            }
        }
    }
    
    public func stopScanning() {
        stopScanningCallCount += 1
        isScanning = false
    }
    
    public func startAdvertising(withName name: String) {
        startAdvertisingCallCount += 1
        isAdvertising = true
    }
    
    public func stopAdvertising() {
        stopAdvertisingCallCount += 1
        isAdvertising = false
    }
    
    public func connect(to device: BLEDevice) {
        connectCallCount += 1
        
        if shouldConnectionSucceed {
            var connectedDevice = device
            connectedDevice.isConnected = true
            connectedDevices.append(connectedDevice)
            
            // Remove from discovered if present
            discoveredDevices.removeAll { $0.id == device.id }
            
            delegate?.provider(self, didConnectTo: connectedDevice)
        } else {
            let error = BLEError.connectionFailed(device: device, reason: "Mock connection failure")
            delegate?.provider(self, didEncounterError: error)
        }
    }
    
    public func disconnect(from device: BLEDevice) {
        disconnectCallCount += 1
        connectedDevices.removeAll { $0.id == device.id }
        
        var disconnectedDevice = device
        disconnectedDevice.isConnected = false
        
        delegate?.provider(self, didDisconnectFrom: disconnectedDevice, error: nil)
    }
    
    public func disconnectAll() {
        for device in connectedDevices {
            disconnect(from: device)
        }
    }
    
    public func sendMessage(_ message: BLEMessage, to device: BLEDevice) throws {
        sendMessageCallCount += 1
        
        sentMessages.append((message, device))
        
        if !shouldSendSucceed {
            throw BLEError.sendFailed(device: device, reason: "Mock send failure")
        }
    }
    
    public func broadcastMessage(_ message: BLEMessage) throws {
        for device in connectedDevices {
            try sendMessage(message, to: device)
        }
    }
    
    public func clearDiscoveredDevices() {
        discoveredDevices.removeAll()
    }
    
    // MARK: - Test Helpers
    
    /// Simulate receiving a message from a device
    public func simulateReceiveMessage(_ message: BLEMessage, from device: BLEDevice) {
        delegate?.provider(self, didReceive: message, from: device)
    }
    
    /// Simulate RSSI update for a device
    public func simulateRSSIUpdate(_ rssi: Int, for deviceId: String) {
        delegate?.provider(self, didUpdateRSSI: rssi, for: deviceId)
    }
    
    /// Simulate device disconnection
    public func simulateDisconnect(from device: BLEDevice, error: Error?) {
        connectedDevices.removeAll { $0.id == device.id }
        delegate?.provider(self, didDisconnectFrom: device, error: error)
    }
    
    /// Reset all state
    public func reset() {
        isScanning = false
        isAdvertising = false
        discoveredDevices.removeAll()
        connectedDevices.removeAll()
        sentMessages.removeAll()
        
        startScanningCallCount = 0
        stopScanningCallCount = 0
        startAdvertisingCallCount = 0
        stopAdvertisingCallCount = 0
        connectCallCount = 0
        disconnectCallCount = 0
        sendMessageCallCount = 0
    }
    
    // MARK: - Private
    
    private func defaultMockDevices() -> [BLEDevice] {
        return [
            BLEDevice(id: "mock-1", name: "Walkie-iPhone", rssi: -65, isConnected: false),
            BLEDevice(id: "mock-2", name: "Walkie-iPad", rssi: -75, isConnected: false),
            BLEDevice(id: "mock-3", name: "Other-Device", rssi: -80, isConnected: false)
        ]
    }
}

// MARK: - Mock Device Builder

public extension MockBLEProvider {
    
    /// Configure with Walkie devices
    func configureForWalkieDevices() {
        mockDevices = [
            BLEDevice(id: UUID().uuidString, name: "Walkie-iPhone", rssi: -60, isConnected: false),
            BLEDevice(id: UUID().uuidString, name: "Walkie-iPad", rssi: -70, isConnected: false)
        ]
    }
    
    /// Configure with specific device count
    func configureWithDeviceCount(_ count: Int, prefix: String = "Device") {
        mockDevices = (0..<count).map { index in
            BLEDevice(
                id: UUID().uuidString,
                name: "\(prefix)-\(index + 1)",
                rssi: -60 - (index * 10),
                isConnected: false
            )
        }
    }
}
