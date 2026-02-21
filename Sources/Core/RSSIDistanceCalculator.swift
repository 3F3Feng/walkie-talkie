import Foundation

/// Distance level classification based on proximity
public enum DistanceLevel: String, CaseIterable, Codable {
    case immediate = "immediate"    // < 1 meter
    case near = "near"              // 1-3 meters
    case medium = "medium"          // 3-10 meters
    case far = "far"                // 10-20 meters
    case veryFar = "veryFar"        // > 20 meters
    
    /// Returns a human-readable description
    public var description: String {
        switch self {
        case .immediate: return "Very Close"
        case .near: return "Near"
        case .medium: return "Medium Distance"
        case .far: return "Far"
        case .veryFar: return "Very Far"
        }
    }
    
    /// Returns a color indicator (for UI purposes)
    public var colorIndicator: String {
        switch self {
        case .immediate: return "🔴"
        case .near: return "🟢"
        case .medium: return "🟡"
        case .far: return "🟠"
        case .veryFar: return "⚪"
        }
    }
}

/// Calculator for converting RSSI to distance
public struct RSSIDistanceCalculator {
    
    /// Default measured power (RSSI at 1 meter distance)
    /// Typically ranges from -59 to -69 dBm depending on device
    public static var measuredPower: Double = -65.0
    
    /// Path loss exponent
    /// 2.0 for free space, 2.7-4.3 for indoor environments
    public static var pathLossExponent: Double = 2.5
    
    /// Calculates distance in meters from RSSI value
    /// - Parameter rssi: RSSI value in dBm (negative integer)
    /// - Returns: Distance in meters
    public static func calculate(rssi: Int) -> Double {
        guard rssi < 0 else { return .infinity }
        
        // Path loss model: distance = 10 ^ ((measuredPower - rssi) / (10 * pathLossExponent))
        let distance = pow(10.0, (measuredPower - Double(rssi)) / (10.0 * pathLossExponent))
        
        // Apply reasonable bounds
        return min(max(distance, 0.1), 100.0)
    }
    
    /// Calculates distance with custom calibration parameters
    /// - Parameters:
    ///   - rssi: RSSI value in dBm
    ///   - referenceRSSI: Known RSSI at 1 meter distance
    ///   - factor: Path loss exponent
    /// - Returns: Distance in meters
    public static func calculate(rssi: Int, referenceRSSI: Double, factor: Double) -> Double {
        guard rssi < 0 else { return .infinity }
        
        let ratio = Double(rssi) / referenceRSSI
        let distance = pow(10.0, -ratio / (10.0 * factor))
        
        return min(max(distance, 0.1), 100.0)
    }
    
    /// Returns the distance level classification for a given distance
    /// - Parameter distance: Distance in meters
    /// - Returns: Distance level
    public static func level(distance: Double) -> DistanceLevel {
        switch distance {
        case ..<1.0:
            return .immediate
        case 1.0..<3.0:
            return .near
        case 3.0..<10.0:
            return .medium
        case 10.0..<20.0:
            return .far
        default:
            return .veryFar
        }
    }
    
    /// Calculates distance level directly from RSSI
    /// - Parameter rssi: RSSI value in dBm
    /// - Returns: Distance level
    public static func level(rssi: Int) -> DistanceLevel {
        return level(distance: calculate(rssi: rssi))
    }
}

/// Extension for RSSI smoothing
public struct RSSISmoother {
    private var samples: [Int] = []
    private let maxSamples: Int
    
    /// Initialize with maximum sample count
    /// - Parameter maxSamples: Number of samples to keep (default: 5)
    public init(maxSamples: Int = 5) {
        self.maxSamples = maxSamples
    }
    
    /// Add a new RSSI sample and return smoothed value
    /// - Parameter rssi: New RSSI reading
    /// - Returns: Smoothed RSSI value
    public mutating func add(sample rssi: Int) -> Double {
        samples.append(rssi)
        
        // Keep only the last maxSamples
        if samples.count > maxSamples {
            samples.removeFirst()
        }
        
        return smoothedValue()
    }
    
    /// Calculate smoothed value using trimmed mean
    /// Removes outliers by dropping highest and lowest values
    /// - Returns: Smoothed RSSI value
    public func smoothedValue() -> Double {
        guard samples.count >= 3 else {
            return samples.isEmpty ? 0.0 : Double(samples.reduce(0, +)) / Double(samples.count)
        }
        
        let sorted = samples.sorted()
        // Remove min and max (outlier rejection)
        let trimmed = sorted.dropFirst().dropLast()
        return Double(trimmed.reduce(0, +)) / Double(trimmed.count)
    }
    
    /// Reset all samples
    public mutating func reset() {
        samples.removeAll()
    }
    
    /// Current sample count
    public var sampleCount: Int {
        return samples.count
    }
}
