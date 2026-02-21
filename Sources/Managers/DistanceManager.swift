import Foundation



/// Distance manager that handles RSSI to distance calculations and smoothing
public final class DistanceManager {
    
    // MARK: - Properties
    
    /// RSSI smoothers indexed by device ID
    private var smoothers: [String: RSSISmoother] = [:]
    
    /// Current distances indexed by device ID
    private var distances: [String: Double] = [:]
    
    /// Current distance levels indexed by device ID
    private var levels: [String: DistanceLevel] = [:]
    
    /// Configurable smoothing window size
    public var smoothingWindowSize: Int = 5
    
    /// Configurable device timeout
    public var deviceTimeout: TimeInterval = 30.0
    
    /// Callback when distance is updated
    public var onDistanceUpdated: ((String, Double, DistanceLevel) -> Void)?
    
    /// Callback when a device goes stale
    public var onDeviceStale: ((String) -> Void)?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Update RSSI for a device and get smoothed distance
    /// - Parameters:
    ///   - rssi: Raw RSSI value
    ///   - deviceId: Device identifier
    /// - Returns: Calculated distance in meters
    @discardableResult
    public func updateRSSI(_ rssi: Int, for deviceId: String) -> Double {
        // Get or create smoother
        let smoother = smoothers[deviceId] ?? RSSISmoother(maxSamples: smoothingWindowSize)
        
        // Add sample and get smoothed RSSI
        var mutableSmoother = smoother
        let smoothedRSSI = Int(mutableSmoother.add(sample: rssi))
        smoothers[deviceId] = mutableSmoother
        
        // Calculate distance
        let distance = RSSIDistanceCalculator.calculate(rssi: smoothedRSSI)
        distances[deviceId] = distance
        
        // Get distance level
        let level = RSSIDistanceCalculator.level(distance: distance)
        levels[deviceId] = level
        
        // Notify
        onDistanceUpdated?(deviceId, distance, level)
        
        return distance
    }
    
    /// Get current distance for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Distance in meters, or nil if not tracked
    public func distance(for deviceId: String) -> Double? {
        return distances[deviceId]
    }
    
    /// Get current distance level for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Distance level, or nil if not tracked
    public func level(for deviceId: String) -> DistanceLevel? {
        return levels[deviceId]
    }
    
    /// Get distance and level together
    /// - Parameter deviceId: Device identifier
    /// - Returns: Tuple of (distance, level), or nil if not tracked
    public func distanceAndLevel(for deviceId: String) -> (distance: Double, level: DistanceLevel)? {
        guard let distance = distances[deviceId],
              let level = levels[deviceId] else { return nil }
        return (distance, level)
    }
    
    /// Check if a device is considered stale
    /// - Parameter deviceId: Device identifier
    /// - Returns: True if device has no recent updates
    public func isStale(_ deviceId: String) -> Bool {
        guard let smoother = smoothers[deviceId] else { return true }
        return smoother.sampleCount == 0
    }
    
    /// Remove a device from tracking
    /// - Parameter deviceId: Device identifier
    public func removeDevice(_ deviceId: String) {
        smoothers.removeValue(forKey: deviceId)
        distances.removeValue(forKey: deviceId)
        levels.removeValue(forKey: deviceId)
    }
    
    /// Clear all tracked devices
    public func clearAll() {
        smoothers.removeAll()
        distances.removeAll()
        levels.removeAll()
    }
    
    /// Get all tracked device IDs
    public var trackedDeviceIds: [String] {
        return Array(distances.keys)
    }
    
    /// Get devices sorted by distance (nearest first)
    /// - Returns: Array of (deviceId, distance, level) sorted by distance
    public func devicesSortedByDistance() -> [(deviceId: String, distance: Double, level: DistanceLevel)] {
        return distances.map { (deviceId: $0.key, distance: $0.value, level: levels[$0.key]!) }
            .sorted { $0.distance < $1.distance }
    }
    
    /// Calculate distance without smoothing (for initial reading)
    /// - Parameter rssi: Raw RSSI value
    /// - Returns: Distance in meters
    public func calculateDistance(rssi: Int) -> Double {
        return RSSIDistanceCalculator.calculate(rssi: rssi)
    }
    
    /// Get distance level directly from RSSI
    /// - Parameter rssi: Raw RSSI value
    /// - Returns: Distance level
    public func calculateLevel(rssi: Int) -> DistanceLevel {
        return RSSIDistanceCalculator.level(rssi: rssi)
    }
}
