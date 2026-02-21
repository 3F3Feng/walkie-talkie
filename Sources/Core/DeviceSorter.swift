import Foundation

/// Device sorter for organizing discovered devices
public struct DeviceSorter {
    /// Sort devices with Walkie devices first, then by distance
    public static func byDistance(_ devices: [TrackedDevice]) -> [TrackedDevice] {
        return devices.sorted { device1, device2 in
            if device1.isWalkieDevice != device2.isWalkieDevice {
                return device1.isWalkieDevice
            }
            return device1.distance < device2.distance
        }
    }

    public static func bySignalStrength(_ devices: [TrackedDevice]) -> [TrackedDevice] {
        return devices.sorted { $0.rssi > $1.rssi }
    }

    public static func byLastSeen(_ devices: [TrackedDevice]) -> [TrackedDevice] {
        return devices.sorted { $0.lastSeen > $1.lastSeen }
    }

    public static func walkieOnly(_ devices: [TrackedDevice]) -> [TrackedDevice] {
        return devices.filter { $0.isWalkieDevice }
    }

    public static func nonWalkieOnly(_ devices: [TrackedDevice]) -> [TrackedDevice] {
        return devices.filter { !$0.isWalkieDevice }
    }

    public static func separate(_ devices: [TrackedDevice]) -> (walkie: [TrackedDevice], other: [TrackedDevice]) {
        let walkie = walkieOnly(devices)
        let other = nonWalkieOnly(devices)
        return (walkie, other)
    }

    public static func sortedByWalkieAndDistance(_ devices: [TrackedDevice]) -> (walkie: [TrackedDevice], other: [TrackedDevice]) {
        let separated = separate(devices)
        let sortedWalkie = byDistance(separated.walkie)
        let sortedOther = byDistance(separated.other)
        return (sortedWalkie, sortedOther)
    }

    public static func removeStale(_ devices: [TrackedDevice], timeout: TimeInterval = 30.0) -> [TrackedDevice] {
        let cutoff = Date().addingTimeInterval(-timeout)
        return devices.filter { $0.lastSeen > cutoff }
    }

    public static func merge(existing: [TrackedDevice], updated: [TrackedDevice]) -> [TrackedDevice] {
        var result = existing
        for newDevice in updated {
            if let index = result.firstIndex(where: { $0.id == newDevice.id }) {
                result[index] = newDevice
            } else {
                result.append(newDevice)
            }
        }
        return result
    }
}
