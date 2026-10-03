import XCTest
@testable import CodexProfileCore

final class CodexDesktopLifecycleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        self.root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codex-desktop-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.root)
    }

    func testNestedCodexCLILayoutIsPreferred() throws {
        let app = try self.makeApp(cliRelativePaths: [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex",
        ])
        let cli = try CodexDesktopLifecycle(environment: ["CODEX_APP": app.path]).resolveBundledCLI()
        XCTAssertTrue(cli.hasSuffix("codex-cli/CodexCLI.app/Contents/MacOS/codex"))
    }

    func testLegacyCodexCLILayoutStillResolves() throws {
        let app = try self.makeApp(cliRelativePaths: ["Contents/Resources/codex"])
        let cli = try CodexDesktopLifecycle(environment: ["CODEX_APP": app.path]).resolveBundledCLI()
        XCTAssertTrue(cli.hasSuffix("Contents/Resources/codex"))
        XCTAssertFalse(cli.contains("codex-cli"))
    }

    func testWrapperOverrideBelongsToTheSameInstallation() throws {
        let app = try self.makeApp(cliRelativePaths: [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex-cli/bin/codex",
        ])
        let wrapper = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path
        let cli = try CodexDesktopLifecycle(environment: [
            "CODEX_APP": app.path,
            "CODEX_BUNDLED_CLI": wrapper,
        ]).resolveBundledCLI()
        XCTAssertTrue(cli.hasSuffix("codex-cli/bin/codex"))
    }

    func testNestedCLIOverrideFindsEnclosingDesktopApp() throws {
        let app = try self.makeApp(cliRelativePaths: [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ])
        let nested = app.appendingPathComponent(
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex").path
        let cli = try CodexDesktopLifecycle(environment: ["CODEX_BUNDLED_CLI": nested]).resolveBundledCLI()
        XCTAssertTrue(cli.hasSuffix("codex-cli/CodexCLI.app/Contents/MacOS/codex"))
    }

    func testMissingCLIReportsTheCurrentPath() throws {
        let app = try self.makeApp(cliRelativePaths: [])
        XCTAssertThrowsError(
            try CodexDesktopLifecycle(environment: ["CODEX_APP": app.path]).resolveBundledCLI()
        ) { error in
            XCTAssertTrue("\(error)".contains("codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        }
    }

    private func makeApp(cliRelativePaths: [String]) throws -> URL {
        let app = self.root.appendingPathComponent("ChatGPT.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS", isDirectory: true),
            withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.openai.codex</string>
        <key>CFBundleExecutable</key><string>ChatGPT</string>
        </dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try self.writeExecutable(contents.appendingPathComponent("MacOS/ChatGPT"))
        for relativePath in cliRelativePaths {
            try self.writeExecutable(app.appendingPathComponent(relativePath))
        }
        return app
    }

    private func writeExecutable(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
