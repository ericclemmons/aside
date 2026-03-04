import XCTest
@testable import AsideCore

final class PlaceholderTests: XCTestCase {
    func testModelsExist() {
        // Verify core types compile
        let context = ActiveContext(appName: "Test", windowTitle: "Window")
        XCTAssertEqual(context.appName, "Test")

        let server = DiscoveredServer(host: "127.0.0.1", port: 4096, username: "user", password: "pass")
        XCTAssertEqual(server.attachTarget, "http://127.0.0.1:4096")

        let status = PermissionStatus()
        XCTAssertFalse(status.allGranted)
    }
}
