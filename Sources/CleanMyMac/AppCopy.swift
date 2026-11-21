import Foundation

enum InterfaceLanguage: Equatable, Sendable {
    case english
    case portuguese

    /// English is the default. Portuguese is selected only when it appears in the
    /// preferred-language list before any English identifier.
    static func resolve(preferredLanguages: [String]) -> InterfaceLanguage {
        for raw in preferredLanguages {
            let identifier = raw.replacingOccurrences(of: "_", with: "-").lowercased()
            if identifier == "en" || identifier.hasPrefix("en-") {
                return .english
            }
            if identifier == "pt" || identifier.hasPrefix("pt-") {
                return .portuguese
            }
        }
        return .english
    }
}

enum InterfaceCopy {
    static var language: InterfaceLanguage {
        let codes = Bundle.main.localizations
        let bundleDeclaresBoth = codes.contains("en") && codes.contains { code in
            let identifier = code.replacingOccurrences(of: "_", with: "-").lowercased()
            return identifier == "pt" || identifier.hasPrefix("pt-")
        }
        let preferred = bundleDeclaresBoth
            ? Bundle.main.preferredLocalizations
            : Locale.preferredLanguages
        return InterfaceLanguage.resolve(preferredLanguages: preferred)
    }

    static func text(_ english: String, portuguese: String) -> String {
        switch language {
        case .english:
            english
        case .portuguese:
            portuguese
        }
    }
}
