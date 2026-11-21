import CleanMyMacCore
import SwiftUI

enum Palette {
    static let safe = Color(red: 0.247, green: 0.749, blue: 0.561)
    static let watch = Color(red: 0.910, green: 0.651, blue: 0.227)
    static let critical = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let hairline = Color.primary.opacity(0.09)
}

extension StorageLevel {
    var tone: Color {
        switch self {
        case .normal: Palette.safe
        case .warning: Palette.watch
        case .critical: Palette.critical
        }
    }
}

extension MemoryLevel {
    var tone: Color {
        switch self {
        case .normal: Palette.safe
        case .warning: Palette.watch
        case .critical: Palette.critical
        }
    }
}

enum Typeface {
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
    static let eyebrow: Font = .system(size: 10, weight: .bold)
}
