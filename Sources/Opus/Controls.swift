import SwiftUI

/// Use the system's rounded controls, including Liquid Glass where available.
struct RoundedControls: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}
extension View {
    func roundedControls() -> some View { modifier(RoundedControls()) }
}
