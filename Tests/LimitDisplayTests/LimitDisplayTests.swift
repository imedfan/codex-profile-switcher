@testable import CodexProfileSwitcherApp
import Foundation
import Testing

@Suite("Limit display mode")
struct LimitDisplayModeTests {

    @Test("used mode shows the reported percent unchanged: 0 is full, 100 is exhausted")
    func usedShowsPercentUnchanged() {
        #expect(LimitDisplayMode.used.displayedPercent(forUsedPercent: 0) == 0)
        #expect(LimitDisplayMode.used.displayedPercent(forUsedPercent: 42) == 42)
        #expect(LimitDisplayMode.used.displayedPercent(forUsedPercent: 100) == 100)
    }

    @Test("remaining mode inverts the percent: 100 is full, 0 is exhausted")
    func remainingInvertsPercent() {
        #expect(LimitDisplayMode.remaining.displayedPercent(forUsedPercent: 0) == 100)
        #expect(LimitDisplayMode.remaining.displayedPercent(forUsedPercent: 42) == 58)
        #expect(LimitDisplayMode.remaining.displayedPercent(forUsedPercent: 100) == 0)
    }

    @Test("both modes clamp percentages to the supported range")
    func clampsOutOfRangePercentages() {
        #expect(LimitDisplayMode.used.displayedPercent(forUsedPercent: -5) == 0)
        #expect(LimitDisplayMode.used.displayedPercent(forUsedPercent: 105) == 100)
        #expect(LimitDisplayMode.remaining.displayedPercent(forUsedPercent: -5) == 100)
        #expect(LimitDisplayMode.remaining.displayedPercent(forUsedPercent: 105) == 0)
    }

    @Test("every mode has a settings label and description")
    func labelsCoverAllCases() {
        for mode in LimitDisplayMode.allCases {
            #expect(!mode.title.isEmpty)
            #expect(!mode.settingsDescription.isEmpty)
        }
    }
}

@Suite("QuotaPilot menu icon")
struct MenuIconRenderingTests {
    @Test("loads the supplied artwork as a native template icon")
    func templateIconLoads() {
        let assets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets")
        #expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent(IconRenderer.iconName).path))
        let image = IconRenderer.render(resourceDirectory: assets)
        #expect(image.isValid)
        #expect(image.isTemplate)
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
    }
}

@Suite("Limit display preferences")
@MainActor
struct LimitDisplayPreferencesTests {

    @Test("defaults to used when nothing is stored")
    func defaultsToUsed() {
        let defaults = Self.makeDefaults()
        #expect(LimitDisplayPreferences(defaults: defaults).mode == .used)
    }

    @Test("persists the selected mode across instances")
    func persistsSelection() {
        let defaults = Self.makeDefaults()
        LimitDisplayPreferences(defaults: defaults).mode = .remaining
        #expect(LimitDisplayPreferences(defaults: defaults).mode == .remaining)
    }

    @Test("falls back to used for an unrecognized stored value")
    func fallsBackOnUnrecognizedValue() {
        let defaults = Self.makeDefaults()
        defaults.set("bogus", forKey: "limitDisplayMode")
        #expect(LimitDisplayPreferences(defaults: defaults).mode == .used)
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "LimitDisplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
