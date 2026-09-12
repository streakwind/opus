import Foundation
import OpusCore

package struct RGBA: Equatable, Sendable {
    package var red: Double
    package var green: Double
    package var blue: Double
    package var alpha: Double
    package init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    package var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

package enum CourseColor {
    package static let names = ["blue", "purple", "pink", "orange", "red", "brown", "green", "teal", "indigo", "cyan", "mint", "yellow"]
    package static func rgba(for color: String) -> RGBA {
        if color.hasPrefix("#"), color.count == 7, let number = UInt32(color.dropFirst(), radix: 16) {
            return RGBA(
                red: Double((number >> 16) & 0xFF) / 255,
                green: Double((number >> 8) & 0xFF) / 255,
                blue: Double(number & 0xFF) / 255
            )
        }
        switch color {
        case "purple": return RGBA(red: 0.47, green: 0.30, blue: 0.76)
        case "pink": return RGBA(red: 0.78, green: 0.30, blue: 0.52)
        case "orange": return RGBA(red: 0.87, green: 0.43, blue: 0.16)
        case "red": return RGBA(red: 0.78, green: 0.25, blue: 0.28)
        case "brown": return RGBA(red: 0.58, green: 0.39, blue: 0.27)
        case "green": return RGBA(red: 0.20, green: 0.58, blue: 0.38)
        case "teal": return RGBA(red: 0.13, green: 0.57, blue: 0.61)
        case "indigo": return RGBA(red: 0.35, green: 0.34, blue: 0.84)
        case "cyan": return RGBA(red: 0.18, green: 0.64, blue: 0.76)
        case "mint": return RGBA(red: 0.20, green: 0.70, blue: 0.58)
        case "yellow": return RGBA(red: 0.86, green: 0.68, blue: 0.14)
        default: return RGBA(red: 0.25, green: 0.48, blue: 0.86)
        }
    }
}

extension Course {
    package var rgba: RGBA { CourseColor.rgba(for: color) }
}
