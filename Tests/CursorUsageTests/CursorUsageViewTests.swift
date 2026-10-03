import Cocoa
import SwiftUI
import XCTest
@testable import CodexProfileSwitcherApp

@MainActor
final class CursorUsageViewTests: XCTestCase {
    func testMenuFitsCompactRowsAndErrorStates() throws {
        let cases: [(String, CursorUsageSnapshot?, CursorUsageError?)] = [
            ("loaded", sampleSnapshot(), nil),
            ("stale", sampleSnapshot(), .network),
            ("signed-out", nil, .signedOut),
        ]
        for (name, snapshot, error) in cases {
            for mode in LimitDisplayMode.allCases {
                let view = CursorUsageView(snapshot: snapshot, teamName: "Example work team with a long name",
                                           error: error, isRefreshing: false, displayMode: mode)
                let host = NSHostingView(rootView: view)
                XCTAssertEqual(host.fittingSize.width, 290, accuracy: 1)
                XCTAssertGreaterThan(host.fittingSize.height, 35)
                XCTAssertLessThan(host.fittingSize.height, 140)
                if name == "loaded" {
                    XCTAssertLessThanOrEqual(host.fittingSize.height, 78, "The normal card must remain compact")
                }
                guard let directory = ProcessInfo.processInfo.environment["CURSOR_MENU_PREVIEW_DIR"] else { continue }
                for scheme in [ColorScheme.light, .dark] {
                    let content = view
                        .environment(\.colorScheme, scheme)
                        .background(scheme == .dark ? Color(nsColor: .darkGray) : .white)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.nsImage)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let url = URL(fileURLWithPath: directory, isDirectory: true)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try png.write(to: url.appendingPathComponent("cursor-\(name)-\(mode.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
