import Testing
import Foundation
@testable import recards

@Suite("Поиск языка")
struct LanguageCatalogTests {

    private let languages = [
        LanguageOption(code: "de-DE", displayName: "немецкий (Германия)"),
        LanguageOption(code: "de-AT", displayName: "немецкий (Австрия)"),
        LanguageOption(code: "fr-FR", displayName: "французский (Франция)"),
        LanguageOption(code: "en-GB", displayName: "английский (Великобритания)"),
    ]

    @Test("Пустой запрос возвращает все языки")
    func emptyQuery() {
        #expect(LanguageCatalog.filter(languages, query: "  ") == languages)
    }

    @Test("Ищется по части названия без учёта регистра")
    func byName() {
        let result = LanguageCatalog.filter(languages, query: "НЕМЕЦ")
        #expect(result.map(\.code) == ["de-DE", "de-AT"])
    }

    @Test("Ищется по названию страны и по коду")
    func byCountryAndCode() {
        #expect(LanguageCatalog.filter(languages, query: "австр").map(\.code) == ["de-AT"])
        #expect(LanguageCatalog.filter(languages, query: "en-gb").map(\.code) == ["en-GB"])
    }

    @Test("Диакритика не мешает поиску")
    func diacriticInsensitive() {
        let options = [LanguageOption(code: "fr-FR", displayName: "Français (France)")]
        #expect(LanguageCatalog.filter(options, query: "francais").count == 1)
    }

    @Test("Ничего не найдено — пустой список")
    func noMatch() {
        #expect(LanguageCatalog.filter(languages, query: "японский").isEmpty)
    }
}
