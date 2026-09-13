import AppKit
import SwiftMath

enum MathRenderer {
    static func image(latex: String, display: Bool, color: NSColor, fontSize: CGFloat) -> NSImage? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        prepareFonts()
        let math = MTMathImage(
            latex: trimmed,
            fontSize: fontSize,
            textColor: color,
            labelMode: display ? .display : .text
        )
        return math.asImage().1
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
