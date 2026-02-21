import Foundation



/// Manages device discovery from BLE and other sources
public final class DeviceDiscoveryManager {
    
    // MARK: - Properties
    
    private let provider: BLEProviderProtocol
    private var discoveredDevices: Set<BLEDevice> = []
    private var updateTimer: Timer?
    
    public weak var delegate: DeviceDiscoveryDelegate?
    
    /// Callback when devices list changes
    public var onDevicesUpdated: (([BLEDevice]) -> Void)?
    
    /// Callback when a new device is discovered
    public var onDeviceDiscovered: ((BLEDevice) -> Void)?
    
    /// Whether discovery is currently active
    public var isDiscovering: Bool {
        return provider.isScanning
    }
    
    /// Current discovered devices list
    public var devices: [BLEDevice] {
        return Array(discoveredDevices).sorted { $0.rssi > $1.rssi }
    }
    
    /// Device timeout in seconds (devices not seen within this time are removed)
    public var deviceTimeout: TimeInterval = 30.0
    
    /// Update interval for cleanup timer
    public var updateInterval: TimeInterval = 5.0
    
    // MARK: - Initialization
    
    public init(provider: BLEProviderProtocol) {
        self.provider = provider
        provider.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Start discovering devices
    public func startDiscovery() {
        provider.startScanning()
        startCleanupTimer()
        delegate?.deviceDiscoveryDidStart(self)
    }
    
    /// Stop discovering devices
    public func stopDiscovery() {
        provider.stopScanning()
        stopCleanupTimer()
        delegate?.deviceDiscoveryDidStop(self)
    }
    
    /// Clear all discovered devices
    public func clearDevices() {
        discoveredDevices.removeAll()
        notifyUpdate()
    }
    
    /// Get device by ID
    public func device(withId id: String) -> BLEDevice? {
        return discoveredDevices.first { $0.id == id }
    }
    
    /// Filter devices by name prefix
    public func devices(withNamePrefix prefix: String) -> [BLEDevice] {
        return devices.filter { $0.name.lowercased().hasPrefix(prefix.lowercased()) }
    }
    
    /// Get walkie devices only
    public func walkieDevices() -> [BLEDevice] {
        return devices.filter { $0.name.lowercased().contains("walkie") }
    }
    
    /// Connect to a specific device
    public func connect(to device: BLEDevice) {
        provider.connect(to: device)
    }
    
    // MARK: - Private Methods
    
    private func startCleanupTimer() {
        stopCleanupTimer()
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.cleanupStaleDevices()
        }
    }
    
    private func stopCleanupTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func cleanupStaleDevices() {
        let cutoff = Date().addingTimeInterval(-deviceTimeout)
        let beforeCount = discoveredDevices.count
        discoveredDevices = Set(discoveredDevices.filter { $0.lastSeen > cutoff })
        
        if discoveredDevices.count != beforeCount {
            notifyUpdate()
        }
    }
    
    private func notifyUpdate() {
        let sortedDevices = devices
        onDevicesUpdated?(sortedDevices)
        delegate?.deviceDiscovery(self, didUpdateDevices: sortedDevices)
    }
    
    private func addOrUpdateDevice(_ device: BLEDevice) {
        discoveredDevices.update(with: device)
        onDeviceDiscovered?(device)
        delegate?.deviceDiscovery(self, didDiscover: device)
        notifyUpdate()
    }
}

// MARK: - BLEProviderDelegate

extension DeviceDiscoveryManager: BLEProviderDelegate {
    
    public func provider(_ provider: BLEProviderProtocol, didDiscover device: BLEDevice) {
        var updatedDevice = device
        updatedDevice.lastSeen = Date()
        addOrUpdateDevice(updatedDevice)
    }
    
    public func provider(_ provider: BLEProviderProtocol, didUpdateRSSI rssi: Int, for deviceId: String) {
        guard var device = discoveredDevices.first(where: { $0.id == deviceId }) else { return }
        device.rssi = rssi
        device.lastSeen = Date()
        discoveredDevices.update(with: device)
        notifyUpdate()
    }
    
    public func provider(_ provider: BLEProviderProtocol, didReceive message: BLEMessage, from device: BLEDevice) {
        // Handle device info messages
        if message.type == .deviceInfo {
            do {
                let _: DeviceInfoPayload = try message.decodedPayload()
                var updatedDevice = device
                updatedDevice.rssi = device.rssi
                updatedDevice.lastSeen = Date()
                addOrUpdateDevice(updatedDevice)
            } catch {
                // Silently handle decoding errors
            }
        }
    }
    
    public func provider(_ provider: BLEProviderProtocol, didConnectTo device: BLEDevice) {
        // Remove from discovered once connected
        discoveredDevices.remove(device)
        notifyUpdate()
        delegate?.deviceDiscovery(self, didConnectTo: device)
    }
    
    public func provider(_ provider: BLEProviderProtocol, didDisconnectFrom device: BLEDevice, error: Error?) {
        // Device disconnected - can be rediscovered
        var disconnectedDevice = device
        disconnectedDevice.isConnected = false
        addOrUpdateDevice(disconnectedDevice)
    }
    
    public func provider(_ provider: BLEProviderProtocol, didEncounterError error: BLEError) {
        delegate?.deviceDiscovery(self, didEncounterError: error)
    }
}

// MARK: - Delegate Protocol

public protocol DeviceDiscoveryDelegate: AnyObject {
    func deviceDiscoveryDidStart(_ manager: DeviceDiscoveryManager)
    func deviceDiscoveryDidStop(_ manager: DeviceDiscoveryManager)
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didDiscover device: BLEDevice)
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didUpdateDevices devices: [BLEDevice])
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didConnectTo device: BLEDevice)
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didEncounterError error: BLEError)
}

// MARK: - Default Implementations

public extension DeviceDiscoveryDelegate {
    func deviceDiscoveryDidStart(_ manager: DeviceDiscoveryManager) {}
    func deviceDiscoveryDidStop(_ manager: DeviceDiscoveryManager) {}
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didDiscover device: BLEDevice) {}
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didUpdateDevices devices: [BLEDevice]) {}
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didConnectTo device: BLEDevice) {}
    func deviceDiscovery(_ manager: DeviceDiscoveryManager, didEncounterError error: BLEError) {}
}
