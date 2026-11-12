import Foundation
import AVFoundation

/// Язык, доступный для колоды.
nonisolated struct LanguageOption: Identifiable, Hashable, Sendable {
    /// Код BCP-47, например `de-DE`.
    var id: String { code }
    var code: String
    /// Название на языке интерфейса, например «немецкий (Германия)».
    var displayName: String
}

/// Список языков, из которых пользователь выбирает при создании колоды.
///
/// Список строится на рантайме из установленных в системе голосов и потому не врёт:
/// в нём нет языков, которые приложение не сможет произнести.
nonisolated enum LanguageCatalog {

    /// Языки, отсортированные по названию.
    static func available(locale: Locale = .current) -> [LanguageOption] {
        let codes = Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))

        let options = codes.map { code in
            LanguageOption(code: code, displayName: displayName(for: code, locale: locale))
        }

        return options.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Языки, подходящие под поисковый запрос.
    ///
    /// Ищется по названию и по коду (`de`, `de-AT`) без учёта регистра и диакритики.
    /// Пустой запрос возвращает список целиком.
    static func filter(_ languages: [LanguageOption], query: String) -> [LanguageOption] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return languages }
        let compare: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return languages.filter {
            $0.displayName.range(of: query, options: compare) != nil
                || $0.code.range(of: query, options: compare) != nil
        }
    }

    /// Человекочитаемое название языка. При неудаче возвращается сам код.
    static func displayName(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: code)
            ?? locale.localizedString(forLanguageCode: code)
            ?? code
    }

    /// Голос для произнесения текста на указанном языке.
    ///
    /// Предпочитается голос повышенного качества, если пользователь его скачал:
    /// программно установить такой голос нельзя, но использовать — можно.
    static func preferredVoice(for code: String) -> AVSpeechSynthesisVoice? {
        let matching = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == code }
        guard !matching.isEmpty else { return AVSpeechSynthesisVoice(language: code) }

        let ranking: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
        for quality in ranking {
            if let voice = matching.first(where: { $0.quality == quality }) {
                return voice
            }
        }
        return matching.first
    }

    /// Язык по умолчанию для новой колоды: язык интерфейса, если для него есть голос.
    static func defaultTargetLanguage(locale: Locale = .current) -> String {
        let available = available(locale: locale).map(\.code)
        guard let languageCode = locale.language.languageCode?.identifier else {
            return available.first ?? "en-US"
        }

        if let exact = available.first(where: { $0.hasPrefix(languageCode + "-") }) {
            return exact
        }
        return available.first ?? "en-US"
    }
}
