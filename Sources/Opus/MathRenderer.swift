import AppKit
import SwiftMath

@MainActor enum MathRenderer {
    struct Rendered {
        var image: NSImage
        var descent: CGFloat
    }

    static func image(
        latex: String,
        display: Bool,
        color: NSColor,
        fontSize: CGFloat,
        appearance: NSAppearance? = nil
    ) -> NSImage? {
        render(latex: latex, display: display, color: color, fontSize: fontSize, appearance: appearance)?.image
    }

    static func render(
        latex: String,
        display: Bool,
        color: NSColor,
        fontSize: CGFloat,
        appearance: NSAppearance? = nil
    ) -> Rendered? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        prepareFonts()
        let currentAppearance = appearance ?? NSApp.effectiveAppearance
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        var rendered: Rendered?
        currentAppearance.performAsCurrentDrawingAppearance {
            let math = MTMathImage(
                latex: trimmed,
                fontSize: fontSize,
                textColor: resolved,
                labelMode: display ? .display : .text
            )
            guard let image = math.asImage().1 else { return }
            let label = MTMathUILabel()
            label.labelMode = display ? .display : .text
            label.fontSize = fontSize
            label.textColor = resolved
            label.latex = trimmed
            label.layout()
            rendered = Rendered(
                image: image,
                descent: label.displayList?.descent ?? max(2, fontSize * 0.2)
            )
        }
        return rendered
    }

    /// SwiftMath looks for its font bundle beside the .app or at the SPM build
    /// path baked into the binary. Packaged apps keep it in Contents/Resources.
    static func prepareFonts() {
        let destinations = [
            "/tmp/opus-release/arm64-apple-macosx/release/SwiftMath_SwiftMath.bundle",
            "/tmp/opus-release/x86_64-apple-macosx/release/SwiftMath_SwiftMath.bundle"
        ]
        if destinations.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return }
        guard let source = Bundle.main.url(forResource: "SwiftMath_SwiftMath", withExtension: "bundle") else { return }
        for path in destinations {
            let dest = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: source, to: dest)
        }
    }
}
