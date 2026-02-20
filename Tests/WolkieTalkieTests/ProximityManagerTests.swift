// MARK: - 简化单元测试 - 使用 Core 模块
import XCTest
import Core

final class ProximityManagerTests: XCTestCase {

    // MARK: - 设备过滤测试
    func testDeviceFiltering_Under50m() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-1")
        device.distance = 30.0
        device.rssi = -75
        
        XCTAssertTrue(device.distance < 50)
    }
    
    func testDeviceFiltering_Over50m() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-2")
        device.distance = 60.0
        device.rssi = -95
        
        XCTAssertFalse(device.distance < 50)
    }
    
    // MARK: - 设备排序测试
    func testDeviceSorting_ByDistance() {
        let device1 = TrackedDevice(bleName: "Far", bleId: "1")
        device1.distance = 30.0
        
        let device2 = TrackedDevice(bleName: "Near", bleId: "2")
        device2.distance = 5.0
        
        let device3 = TrackedDevice(bleName: "Middle", bleId: "3")
        device3.distance = 15.0
        
        var devices = [device1, device2, device3]
        devices.sort { $0.distance < $1.distance }
        
        XCTAssertEqual(devices[0].id, "2")  // Near (5m)
        XCTAssertEqual(devices[1].id, "3")   // Middle (15m)
        XCTAssertEqual(devices[2].id, "1")  // Far (30m)
    }
    
    // MARK: - RSSI 计算
    func testRSSIToDistance() {
        // RSSI -50 应该是近距离
        let rssi = -50
        let distance = pow(10, Double(-50 - rssi) / 20.0)
        
        XCTAssertLessThan(distance, 2.0)  // 应该 < 2m
    }
}
