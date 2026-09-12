import SwiftUI
import AppKit
import OpusCore

extension Course {
    static let colors = ["blue", "purple", "pink", "orange", "red", "brown", "green", "teal", "indigo", "cyan", "mint", "yellow"]
    static func hexColor(_ value: String) -> Color? {
        guard value.hasPrefix("#"), value.count == 7 else { return nil }
        let hex = value.dropFirst()
        guard let number = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
    static func hex(from color: Color) -> String {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
    var tint: Color {
        if let custom = Self.hexColor(color) { return custom }
        switch color {
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "cyan": return .cyan
        case "mint": return .mint
        case "yellow": return .yellow
        default: return .blue
        }
    }
    var scheduleGradient: LinearGradient {
        if let custom = Self.hexColor(color) {
            return LinearGradient(colors: [custom, custom.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let colors: [Color]
        switch color {
        case "purple": colors = [Color(red: 0.47, green: 0.30, blue: 0.76), Color(red: 0.39, green: 0.23, blue: 0.66)]
        case "pink": colors = [Color(red: 0.78, green: 0.30, blue: 0.52), Color(red: 0.68, green: 0.22, blue: 0.44)]
        case "orange": colors = [Color(red: 0.87, green: 0.43, blue: 0.16), Color(red: 0.76, green: 0.34, blue: 0.10)]
        case "red": colors = [Color(red: 0.78, green: 0.25, blue: 0.28), Color(red: 0.68, green: 0.18, blue: 0.22)]
        case "brown": colors = [Color(red: 0.58, green: 0.39, blue: 0.27), Color(red: 0.49, green: 0.31, blue: 0.21)]
        case "green": colors = [Color(red: 0.20, green: 0.58, blue: 0.38), Color(red: 0.14, green: 0.48, blue: 0.31)]
        case "teal": colors = [Color(red: 0.13, green: 0.57, blue: 0.61), Color(red: 0.09, green: 0.47, blue: 0.52)]
        case "indigo": colors = [Color(red: 0.35, green: 0.34, blue: 0.84), Color(red: 0.27, green: 0.25, blue: 0.72)]
        case "cyan": colors = [Color(red: 0.18, green: 0.64, blue: 0.76), Color(red: 0.12, green: 0.52, blue: 0.64)]
        case "mint": colors = [Color(red: 0.20, green: 0.70, blue: 0.58), Color(red: 0.14, green: 0.58, blue: 0.48)]
        case "yellow": colors = [Color(red: 0.86, green: 0.68, blue: 0.14), Color(red: 0.74, green: 0.56, blue: 0.08)]
        default: colors = [Color(red: 0.25, green: 0.48, blue: 0.86), Color(red: 0.18, green: 0.38, blue: 0.76)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Course {
    var shortName: String {
        name
    }
}
