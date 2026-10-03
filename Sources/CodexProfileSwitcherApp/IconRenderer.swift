import Cocoa

// NSStatusBar tints template images for the current appearance and selection.
enum IconRenderer {
    static let iconName = "QuotaPilotMenuTemplate.png"
    private static let iconSize = NSSize(width: 18, height: 18)

    static func render(resourceDirectory: URL? = nil) -> NSImage {
        let directories = [
            resourceDirectory,
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }
        let image = directories.lazy
            .compactMap { NSImage(contentsOf: $0.appendingPathComponent(iconName)) }
            .first ?? NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: AppInfo.name)!
        image.size = iconSize
        image.isTemplate = true
        return image
    }
}
