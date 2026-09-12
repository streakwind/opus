import OpusCore
import SwiftUI
import AppKit

/// Use the system's rounded controls, including Liquid Glass where available.
struct RoundedControls: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        #else
        content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        #endif
    }
}
extension View {
    func roundedControls() -> some View { modifier(RoundedControls()) }
}

struct EditorCardBackdrop<Content: View>: View {
    @ViewBuilder var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(100)
    }
}

struct EditorCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }
}
extension View {
    func editorCard() -> some View { modifier(EditorCard()) }
}

struct PillChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75) }
    }
}
extension View {
    func pillChrome() -> some View { modifier(PillChrome()) }
}

enum RepeatBadgeStyle { case background, fill }
struct RepeatBadge: View {
    var style: RepeatBadgeStyle = .background
    var body: some View {
        Image(systemName: "repeat")
            .font(.system(size: style == .fill ? 8 : 10, weight: .semibold))
            .foregroundStyle(style == .fill ? Color.white.opacity(0.9) : Color.primary.opacity(0.58))
            .accessibilityLabel("Repeating")
    }
}

struct PillPicker<Value: Hashable, Options: View>: View {
    var title: String
    var label: String
    @Binding var selection: Value
    @ViewBuilder var options: Options
    init(_ title: String, label: String, selection: Binding<Value>, @ViewBuilder content: () -> Options) {
        self.title = title; self.label = label; _selection = selection; options = content()
    }
    var body: some View {
        Menu { Picker(title, selection: $selection) { options }.pickerStyle(.inline) } label: { Text(label) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .pillChrome()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(title + ": " + label)
    }
}


struct TimeControl: View {
    @Binding var minutes: Int
    @State private var editing = false
    var body: some View {
        Button(ClockTime.label(minutes)) { editing = true }
            .buttonStyle(.plain)
            .pillChrome()
            .fixedSize()
            .popover(isPresented: $editing) {
                VStack(spacing: 12) {
                    DatePicker("Time", selection: Binding(get: { ClockTime.date(minutes) }, set: { minutes = ClockTime.minutes($0) }), displayedComponents: .hourAndMinute)
                    Button("Done") { editing = false }.keyboardShortcut(.defaultAction)
                }.padding(16).roundedControls()
            }
    }
}

struct WindowChrome: NSViewRepresentable {
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarSeparatorStyle = .none
        }
    }
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) { nsView.window?.titlebarSeparatorStyle = .none }
}
