// MARK: - TrackedDevice 单元测试
import XCTest
import Core

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif

final class TrackedDeviceTests: XCTestCase {

    // MARK: - 初始化测试
    #if canImport(MultipeerConnectivity)
    func testInit_WithPeerID() {
        let peerID = MCPeerID(displayName: "TestDevice")
        let device = TrackedDevice(peerID: peerID)
        
        XCTAssertEqual(device.displayName, "TestDevice")
        XCTAssertEqual(device.id, "TestDevice")
    }
    #endif
    
    func testInit_WithBLE() {
        let device = TrackedDevice(bleName: "BLEDevice", bleId: "ble-123")
        
        XCTAssertEqual(device.displayName, "BLEDevice")
        XCTAssertEqual(device.id, "ble-123")
    }
    
    // MARK: - 距离更新测试
    func testDistanceUpdate() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-1")
        
        device.distance = 5.0
        XCTAssertEqual(device.distance, 5.0)
        
        device.distance = 10.5
        XCTAssertEqual(device.distance, 10.5)
    }
    
    // MARK: - RSSI 更新测试
    func testRSSIUpdate() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-2")
        
        device.rssi = -60
        XCTAssertEqual(device.rssi, -60)
    }
    
    // MARK: - 配对状态测试
    func testPairingState_Default() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-3")
        XCTAssertEqual(device.pairingState, .none)
    }
    
    func testPairingState_Pending() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-4")
        device.pairingState = .pending
        XCTAssertEqual(device.pairingState, .pending)
    }
    
    // MARK: - Provider Type 测试
    func testProviderType_Default() {
        let device = TrackedDevice(bleName: "Test", bleId: "test-5")
        XCTAssertEqual(device.providerType, .bluetooth)
    }
}
