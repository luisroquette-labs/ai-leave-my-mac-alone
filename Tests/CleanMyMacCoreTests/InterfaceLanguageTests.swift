import Testing
@testable import CleanMyMac

@Test func interfaceLanguageDefaultsToEnglish() {
    #expect(InterfaceLanguage.resolve(preferredLanguages: []) == .english)
    #expect(InterfaceLanguage.resolve(preferredLanguages: ["fr-FR", "de"]) == .english)
    #expect(InterfaceLanguage.resolve(preferredLanguages: ["en-US", "pt-BR"]) == .english)
    #expect(InterfaceLanguage.resolve(preferredLanguages: ["pt-BR"]) == .portuguese)
    #expect(InterfaceLanguage.resolve(preferredLanguages: ["pt_PT", "en"]) == .portuguese)
}
