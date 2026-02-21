import Foundation
import Combine




/// WalkieCoreBridge
/// Provides backward-compatible bridge from new SPM architecture to legacy app code
/// Replaces the old BLEManager with modular DeviceDiscoveryManager + PairingManager + DistanceManager
public final class WalkieCoreBridge: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = WalkieCoreBridge()
    
    // MARK: - Published Properties (Legacy-compatible)
    
    /// All discovered devices, sorted by proximity
    @Published public private(set) var discoverableDevices: [BLEDevice] = []
    
    /// Currently paired devices
    @Published public private(set) var pairedDevicesList: [PairedDevice] = []
    
    /// Current pairing mode state
    @Published public private(set) var isInPairingMode: Bool = false
    
    /// BLE scanning state
    @Published public private(set) var isScanning: Bool = false
    
    /// Connection errors
    @Published public var lastError: Error?
    
    // MARK: - Internal Components (New Architecture)
    
    private let deviceDiscoveryManager: DeviceDiscoveryManager
    private let pairingManager: PairingManager
    private let distanceManager: DistanceManager
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Initialize with default BLE provider (mock for bridge - real app provides real provider)
        let bleProvider = MockWalkieBLEProvider()
        
        self.deviceDiscoveryManager = DeviceDiscoveryManager(provider: bleProvider)
        self.pairingManager = PairingManager(provider: bleProvider)
        self.distanceManager = DistanceManager()
        
        setupBindings()
    }
    
    /// Initialize with custom BLE provider (for testing/mocking)
    public init(provider: BLEProviderProtocol) {
        self.deviceDiscoveryManager = DeviceDiscoveryManager(provider: provider)
        self.pairingManager = PairingManager(provider: provider)
        self.distanceManager = DistanceManager()
        
        setupBindings()
    }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        // Bridge DeviceDiscoveryManager discoveries to legacy API
        deviceDiscoveryManager.onDevicesUpdated = { [weak self] devices in
            DispatchQueue.main.async {
                self?.discoverableDevices = devices
            }
        }
        
        // Bridge PairingManager state
        pairingManager.onPairedDevicesUpdated = { [weak self] paired in
            DispatchQueue.main.async {
                self?.pairedDevicesList = paired
                self?.isInPairingMode = self?.pairingManager.isInPairingMode ?? false
            }
        }
    }
    
    // MARK: - Legacy API Methods (Device Discovery)
    
    /// Start scanning for WalkieTalkie devices
    public func startScanning() {
        deviceDiscoveryManager.startDiscovery()
        isScanning = true
    }
    
    /// Stop scanning
    public func stopScanning() {
        deviceDiscoveryManager.stopDiscovery()
        isScanning = false
    }
    
    /// Refresh device list manually
    public func refreshDevices() {
        deviceDiscoveryManager.clearDevices()
        deviceDiscoveryManager.startDiscovery()
    }
    
    /// Get Walkie-specific devices only
    public func walkieDevices() -> [BLEDevice] {
        return deviceDiscoveryManager.walkieDevices()
    }
    
    /// Get device by ID
    public func device(withId id: String) -> BLEDevice? {
        return deviceDiscoveryManager.device(withId: id)
    }
    
    // MARK: - Legacy API Methods (Pairing)
    
    /// Enter pairing mode (start advertising + accepting pair requests)
    public func startPairingMode() {
        pairingManager.startPairingMode()
        isInPairingMode = true
    }
    
    /// Exit pairing mode
    public func stopPairingMode() {
        pairingManager.stopPairingMode()
        isInPairingMode = false
    }
    
    /// Send pairing request to a specific device
    /// - Parameter device: The device to pair with
    public func requestPairing(with device: BLEDevice) {
        pairingManager.requestPairing(with: device)
    }
    
    /// Accept incoming pairing request
    /// - Parameter request: The pairing request to accept
    public func acceptPairing(_ request: PairingRequestPayload) {
        pairingManager.acceptPairing(request)
    }
    
    /// Reject pairing request
    /// - Parameter request: The pairing request to reject
    public func rejectPairing(_ request: PairingRequestPayload) {
        pairingManager.rejectPairing(request)
    }
    
    /// Unpair a device
    /// - Parameter deviceId: The device ID to unpair
    public func unpair(deviceId: String) {
        pairingManager.unpair(with: deviceId)
    }
    
    /// Check if device is paired
    /// - Parameter deviceId: Device ID to check
    /// - Returns: True if paired
    public func isPaired(deviceId: String) -> Bool {
        return pairingManager.isPaired(deviceId: deviceId)
    }
    
    // MARK: - Legacy API Methods (Distance)
    
    /// Get real-time distance to a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Distance in meters (nil if unknown)
    public func distance(for deviceId: String) -> Double? {
        return distanceManager.distance(for: deviceId)
    }
    
    /// Get distance level for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Distance level (near/medium/far)
    public func distanceLevel(for deviceId: String) -> DistanceLevel? {
        return distanceManager.level(for: deviceId)
    }
    
    /// Update RSSI and get smoothed distance
    /// - Parameters:
    ///   - rssi: Raw RSSI value
    ///   - deviceId: Device identifier
    /// - Returns: Smoothed distance in meters
    @discardableResult
    public func updateRSSI(_ rssi: Int, for deviceId: String) -> Double {
        return distanceManager.updateRSSI(rssi, for: deviceId)
    }
    
    /// Check if device is stale (no recent updates)
    /// - Parameter deviceId: Device identifier
    /// - Returns: True if stale
    public func isDeviceStale(_ deviceId: String) -> Bool {
        return distanceManager.isStale(deviceId)
    }
    
    /// Remove device from distance tracking
    /// - Parameter deviceId: Device identifier
    public func removeDevice(_ deviceId: String) {
        distanceManager.removeDevice(deviceId)
    }
    
    /// Clear all distance tracking
    public func clearDistanceTracking() {
        distanceManager.clearAll()
    }
    
    /// Get devices sorted by distance (nearest first)
    /// - Returns: Array of tuples with device info and distance
    public func devicesSortedByDistance() -> [(deviceId: String, distance: Double, level: DistanceLevel)] {
        return distanceManager.devicesSortedByDistance()
    }
    
    // MARK: - Legacy API Methods (PTT - Push To Talk)
    
    /// Start PTT audio transmission to all paired devices
    public func startPTT() {
        // PTT implementation would go here
        print("WalkieCoreBridge: Start PTT")
    }
    
    /// Stop PTT audio transmission
    public func stopPTT() {
        // PTT implementation would go here
        print("WalkieCoreBridge: Stop PTT")
    }
    
    // MARK: - Legacy Compatibility Helpers
    
    /// Legacy BLEManager-compatible method to get nearby devices
    public var nearbyDevices: [BLEDevice] {
        return discoverableDevices
    }
    
    /// Get all paired devices as BLEDevice-like struct
    public var pairedDevices: [PairedDevice] {
        return pairedDevicesList
    }
    
    /// Legacy method: Check if a device is connected
    /// - Parameter device: The device to check
    /// - Returns: True if device is connected
    public func isConnected(_ device: BLEDevice) -> Bool {
        return device.isConnected
    }
    
    /// Clear any error state
    public func clearError() {
        lastError = nil
    }
    
    // MARK: - Connect/Disconnect
    
    /// Connect to a device
    /// - Parameter device: Device to connect
    public func connect(to device: BLEDevice) {
        deviceDiscoveryManager.connect(to: device)
    }
}

// MARK: - Mock BLE Provider for Bridge

/// Mock BLE provider for when no real provider is available
final class MockWalkieBLEProvider: BLEProviderProtocol {
    weak var delegate: BLEProviderDelegate?
    
    var isScanning: Bool = false
    var isAdvertising: Bool = false
    var discoveredDevices: [BLEDevice] = []
    var connectedDevices: [BLEDevice] = []
    
    func startScanning() {
        isScanning = true
    }
    
    func stopScanning() {
        isScanning = false
    }
    
    func startAdvertising(withName name: String) {
        isAdvertising = true
    }
    
    func stopAdvertising() {
        isAdvertising = false
    }
    
    func connect(to device: BLEDevice) {
        // Mock implementation
    }
    
    func disconnect(from device: BLEDevice) {
        // Mock implementation
    }
    
    func disconnectAll() {
        // Mock implementation
    }
    
    func sendMessage(_ message: BLEMessage, to device: BLEDevice) throws {
        // Mock implementation
    }
    
    func broadcastMessage(_ message: BLEMessage) throws {
        // Mock implementation
    }
    
    func clearDiscoveredDevices() {
        discoveredDevices.removeAll()
    }
}

// MARK: - BLEDevice Extensions

public extension BLEDevice {
    /// Legacy display name helper
    var displayName: String {
        return name.isEmpty ? "Unknown Device" : name
    }
    
    /// Legacy RSSI strength indicator (0-100)
    var signalStrength: Int {
        // Normalize RSSI (-100 to -40) to 0-100 scale
        let normalized = max(0, min(100, Int((Float(rssi) + 100.0) / 60.0 * 100.0)))
        return normalized
    }
    
    /// Convert to TrackedDevice for legacy compatibility
    var asTrackedDevice: TrackedDevice {
        return TrackedDevice(
            id: uuid.uuidString,
            name: name,
            rssi: rssi,
            distance: 0,
            pairingState: PairingState.none,
            providerType: ProviderType.bluetooth,
            lastSeen: lastSeen,
            isConnected: isConnected
        )
    }
}
