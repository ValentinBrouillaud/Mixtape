import SwiftUI

nonisolated enum MixtapeAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    static let defaultsKey = "mixtape.appearance.v47"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

nonisolated enum MixtapePalette {
    static let accent = Color(red: 0.92, green: 0.14, blue: 0.23)
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.055, green: 0.055, blue: 0.06) : Color(red: 0.98, green: 0.98, blue: 0.985)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.115) : Color.white
    }
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.17) : Color(white: 0.93)
    }
}
