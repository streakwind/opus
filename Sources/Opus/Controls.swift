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

struct PillLabel: View {
    var title: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }.padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
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
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75) }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(title + ": " + label)
    }
}


struct TimeControl: View {
    @Binding var minutes: Int
    @State private var editing = false
    var body: some View {
        Button(ClockTime.label(minutes)) { editing = true }.roundedControls()
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
