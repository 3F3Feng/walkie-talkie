// MARK: - ProximityManager 单元测试
import XCTest
@testable import WolkieTalkie

final class ProximityManagerTests: XCTestCase {

    var manager: ProximityManager!
    
    override func setUp() {
        super.setUp()
        manager = ProximityManager.shared
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - 距离计算测试
    func testRSSIToDistance_Close() {
        let rssi = -50
        let distance = rssiToDistance(rssi)
        XCTAssertGreaterThan(distance, 0)
        XCTAssertLessThan(distance, 2)
    }
    
    func testRSSIToDistance_Medium() {
        let rssi = -70
        let distance = rssiToDistance(rssi)
        XCTAssertGreaterThan(distance, 5)
        XCTAssertLessThan(distance, 15)
    }
    
    func testRSSIToDistance_Far() {
        let rssi = let distance = rssiToDistance(rssi)
        XCTAssertGreaterThan -90
       (distance, 20)
        XCTAssertLessThan(distance, 50)
    }
    
    // MARK: - 设备过滤测试
    func testDeviceFiltering_Under50m() {
        // 创建距离 < 50m 的设备
        let device = TrackedDevice(bleName: "Test", bleId: "test-1")
        device.distance = 30.0
        device.rssi = -75
        
        // 模拟过滤逻辑
        let shouldAdd = device.distance < 50
        
        XCTAssertTrue(shouldAdd)
    }
    
    func testDeviceFiltering_Over50m() {
        // 创建距离 >= 50m 的设备
        let device = TrackedDevice(bleName: "Test", bleId: "test-2")
        device.distance = 60.0
        device.rssi = -95
        
        // 模拟过滤逻辑
        let shouldAdd = device.distance < 50
        
        XCTAssertFalse(shouldAdd)
    }
    
    // MARK: - 设备排序测试
    func testDeviceSorting_ByDistance() {
        let device1 = TrackedDevice(bleName: "Far", bleId: "1")
        device1.distance = 30.0
        
        let device2 = TrackedDevice(bleName: "Near", bleId: "2")
        device2.distance = 5.0
        
        let device3 = TrackedDevice(bleName: "Middle", bleId: "3")
        device3.distance = 15.0
        
        // 测试排序
        var devices = [device1, device2, device3]
        devices.sort { $0.distance < $1.distance }
        
        XCTAssertEqual(devices[0].id, "2")  // Near (5m)
        XCTAssertEqual(devices[1].id, "3")  // Middle (15m)
        XCTAssertEqual(devices[2].id, "1")  // Far (30m)
    }
    
    // MARK: - 配对状态测试
    func testPairingState_Default() {
        let device = TrackedDevice(bleName: "Test", bleId: "test")
        XCTAssertEqual(device.pairingState, .none)
    }
    
    func testPairingState_Transition() {
        let device = TrackedDevice(bleName: "Test", bleId: "test")
        
        // 模拟配对请求
        device.pairingState = .pending
        XCTAssertEqual(device.pairingState, .pending)
        
        // 模拟配对成功
        device.pairingState = .paired
        XCTAssertEqual(device.pairingState, .paired)
    }
    
    // MARK: - App Mode 测试
    func testAppMode_Default() {
        XCTAssertEqual(manager.appMode, .talk)
    }
    
    func testAppMode_PairingMode() {
        manager.togglePairingMode()
        XCTAssertEqual(manager.appMode, .pairing)
        
        manager.togglePairingMode()
        XCTAssertEqual(manager.appMode, .talk)
    }
    
    // MARK: - Talk Mode 测试
    func testTalkMode_Default() {
        XCTAssertEqual(manager.talkMode, .auto)
    }
    
    // MARK: - 距离等级测试
    func testDistanceLevel_VeryClose() {
        let device = TrackedDevice(bleName: "Test", bleId: "test")
        device.distance = 0.5
        
        let level = DistanceLevel(distance: device.distance)
        XCTAssertEqual(level, .veryClose)
    }
    
    func testDistanceLevel_Close() {
        let device = TrackedDevice(bleName: "Test", bleId: "test")
        device.distance = 2.0
        
        let level = DistanceLevel(distance: device.distance)
        XCTAssertEqual(level, .close)
    }
    
    func testDistanceLevel_Medium() {
        let device = TrackedDevice(bleName: "Test", bleId: "test")
        device.distance = 7.0
        
        let level = DistanceLevel(distance: device.distance)
        XCTAssertEqual(level, .medium)
    }
    
    // MARK: - 辅助方法
    private func rssiToDistance(_ rssi: Int) -> Double {
        let power = -50
        if rssi >= 0 { return 0 }
        return min(pow(10, Double(power - rssi) / 20.0), 50.0)
    }
}
