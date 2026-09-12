import OpusCore
import SwiftUI
import AppKit

/// Use standard platform controls without decorative glass or custom shadows.
struct RoundedControls: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.bordered)
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
    }
}
extension View {
    func editorCard() -> some View { modifier(EditorCard()) }
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
            .menuStyle(.button)
            .controlSize(.small)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(title + ": " + label)
    }
}


struct TimeControl: View {
    @Binding var minutes: Int
    @State private var editing = false
    var body: some View {
        Button(ClockTime.label(minutes)) { editing = true }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
            apply()
        }
        override func layout() {
            super.layout()
            apply()
        }
        func apply() {
            guard let window else { return }
            window.titlebarSeparatorStyle = .none
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .textBackgroundColor
            unify(window.contentView)
        }
        private func unify(_ view: NSView?) {
            guard let view else { return }
            if let effect = view as? NSVisualEffectView,
               effect.material == .sidebar || effect.material == .titlebar {
                effect.material = .contentBackground
                effect.blendingMode = .behindWindow
                effect.state = .followsWindowActiveState
                effect.isEmphasized = false
            }
            if let table = view as? NSTableView {
                table.backgroundColor = .clear
                table.enclosingScrollView?.drawsBackground = false
                table.selectionHighlightStyle = .none
            }
            view.subviews.forEach { unify($0) }
        }
    }
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) { nsView.apply() }
}
