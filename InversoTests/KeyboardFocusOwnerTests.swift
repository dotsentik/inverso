import XCTest

@testable import Inverso

final class KeyboardFocusOwnerTests: XCTestCase {

    private static let bundleIDs: [pid_t: String] = [
        1: "com.apple.Spotlight",
        2: "com.apple.appkit.xpc.openAndSavePanelService",
        3: "com.apple.TextEdit",
        4: "com.apple.Safari",
        5: "com.apple.WindowManager",
        6: "com.apple.campo",
    ]

    private func window(
        _ pid: pid_t, layer: Int = 0, size: CGSize = CGSize(width: 600, height: 400), alpha: Double = 1
    )
        -> KeyboardFocusOwner.Window
    {
        KeyboardFocusOwner.Window(pid: pid, layer: layer, size: size, alpha: alpha)
    }

    private func overlay(_ windows: [KeyboardFocusOwner.Window], systemFocusPID: pid_t? = nil) -> pid_t? {
        KeyboardFocusOwner.overlayPID(in: windows, bundleID: { Self.bundleIDs[$0] }, systemFocusPID: { systemFocusPID })
    }

    func testIsOverlayProcess() {
        XCTAssertTrue(KeyboardFocusOwner.isOverlayProcess(bundleID: "com.apple.Spotlight"))
        XCTAssertTrue(KeyboardFocusOwner.isOverlayProcess(bundleID: "com.apple.appkit.xpc.openAndSavePanelService"))
        XCTAssertTrue(
            KeyboardFocusOwner.isOverlayProcess(bundleID: "com.apple.appkit.xpc.openAndSavePanelService.Variant"))
        XCTAssertTrue(KeyboardFocusOwner.isOverlayProcess(bundleID: "com.apple.campo"))
        XCTAssertFalse(KeyboardFocusOwner.isOverlayProcess(bundleID: "com.apple.TextEdit"))
        XCTAssertFalse(KeyboardFocusOwner.isOverlayProcess(bundleID: nil))
    }

    func testNormalAppInFront_NoOverlay() {
        XCTAssertNil(overlay([window(4), window(3)]))
    }

    func testSpotlightAboveApps() {
        // Menu bar and other high-level windows sit above Spotlight in the list
        XCTAssertEqual(overlay([window(5, layer: 24), window(1, layer: 8), window(4)]), 1)
    }

    func testSpotlightHost_WithTheSystemFocus() {
        // macOS 27: the Spotlight panel belongs to com.apple.campo, the system-wide focus is in it
        XCTAssertEqual(overlay([window(5, layer: 24), window(6, layer: 23), window(4)], systemFocusPID: 6), 6)
    }

    func testSpotlightHost_WithoutTheSystemFocus_IsIgnored() {
        // A Siri banner of the same process while the user types in Safari
        XCTAssertNil(overlay([window(6, layer: 23), window(4)], systemFocusPID: 4))
        XCTAssertNil(overlay([window(6, layer: 23), window(4)], systemFocusPID: nil))
    }

    func testSpotlightApp_NeedsNoFocusConfirmation() {
        // Older macOS: Spotlight.app, the system-wide focus stays in the app behind
        XCTAssertEqual(overlay([window(1, layer: 8), window(4)], systemFocusPID: 4), 1)
    }

    func testSavePanelInFrontOfItsApp() {
        XCTAssertEqual(overlay([window(2), window(3)]), 2)
    }

    func testSavePanelOfBackgroundApp_IsIgnored() {
        // TextEdit's Save sheet stays on screen while the user types in Safari
        XCTAssertNil(overlay([window(4), window(2), window(3)]))
    }

    func testInvisibleOverlayWindows_AreIgnored() {
        XCTAssertNil(overlay([window(1, layer: 8, alpha: 0), window(4)]))
        XCTAssertNil(overlay([window(2, size: CGSize(width: 1, height: 1)), window(4)]))
    }

    func testNoWindows() {
        XCTAssertNil(overlay([]))
    }

    // MARK: - Typing chunks

    @MainActor
    func testTypingChunks_RespectLimitAndCharacterBoundaries() {
        XCTAssertEqual(CGEventKeystrokeSender.chunks(of: ""), [])
        XCTAssertEqual(CGEventKeystrokeSender.chunks(of: "привет").map(\.count), [6])

        let long = String(repeating: "я", count: 45)
        XCTAssertEqual(CGEventKeystrokeSender.chunks(of: long).map(\.count), [20, 20, 5])

        // 19 letters + an emoji (2 UTF-16 units): the emoji moves to the next chunk whole
        let emoji = String(repeating: "a", count: 19) + "👍"
        let chunks = CGEventKeystrokeSender.chunks(of: emoji)
        XCTAssertEqual(chunks.map(\.count), [19, 2])
        XCTAssertEqual(chunks.flatMap { $0 }, Array(emoji.utf16))
    }
}
