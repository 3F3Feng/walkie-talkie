// MARK: - 最小化单元测试
import XCTest

final class BasicTests: XCTestCase {
    func testAlwaysPass() {
        XCTAssertTrue(true)
    }
    
    func testMath() {
        XCTAssertEqual(1+1, 2)
    }
}
