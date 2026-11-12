import Foundation
import SwiftData

/// Загрузка демо-колод из бандла при первом запуске.
///
/// Колоды ничем не отличаются от пользовательских: их можно править и удалять.
/// Они же служат тестовыми данными при разработке.
@MainActor
enum DemoDeckLoader {

    private static let hasLoadedKey = "demoDecks.loaded"
    private static let hasFilledPartsOfSpeechKey = "demoDecks.partsOfSpeechFilled"
    private static let fileNames = ["de_ru_a1", "en_ru_a1"]

    /// Наполняет пустое хранилище демо-колодами ровно один раз.
    ///
    /// Флаг в `UserDefaults` не даёт вернуть удалённые колоды при следующем запуске.
    static func loadIfNeeded(into context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: hasLoadedKey) else { return }

        // Дополнительная защита: если данные уже есть, ничего не добавляем.
        let existing = (try? context.fetchCount(FetchDescriptor<Deck>())) ?? 0
        guard existing == 0 else {
            UserDefaults.standard.set(true, forKey: hasLoadedKey)
            return
        }

        for name in fileNames {
            guard let payload = loadPayload(named: name) else { continue }
            insert(payload, into: context)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: hasLoadedKey)
    }

    /// Проставляет часть речи словам демо-колод, загруженных до появления этого поля.
    ///
    /// Слово сопоставляется с записью из бандла по `WordKey`. Слова, которые пользователь
    /// переименовал или добавил сам, не трогаются. Выполняется один раз.
    static func fillPartsOfSpeechIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: hasFilledPartsOfSpeechKey) else { return }

        var known: [String: PartOfSpeech] = [:]
        for name in fileNames {
            for item in loadPayload(named: name)?.words ?? [] {
                guard let kind = PartOfSpeech(code: item.partOfSpeech) else { continue }
                known[WordKey.make(text: item.word, translations: item.translations)] = kind
            }
        }

        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for word in decks.filter(\.isBuiltIn).flatMap({ $0.words ?? [] }) where word.partOfSpeech == nil {
            word.partOfSpeech = known[WordKey.make(text: word.text, translations: word.translations)]
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: hasFilledPartsOfSpeechKey)
    }

    static func loadPayload(named name: String) -> DeckPayload? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DeckPayload.self, from: data)
    }

    private static func insert(_ payload: DeckPayload, into context: ModelContext) {
        let deck = Deck(
            name: payload.name,
            emoji: emoji(for: payload.sourceLanguage),
            sourceLanguage: payload.sourceLanguage,
            targetLanguage: payload.targetLanguage,
            isBuiltIn: true
        )
        context.insert(deck)

        for item in payload.words {
            let normalized = item.normalized
            guard !normalized.word.isEmpty, !normalized.translations.isEmpty else { continue }

            let word = Word(
                text: normalized.word,
                translations: normalized.translations,
                transcription: normalized.transcription,
                example: normalized.example,
                exampleTranslation: normalized.exampleTranslation,
                partOfSpeech: PartOfSpeech(code: normalized.partOfSpeech)
            )
            word.deck = deck
            context.insert(word)
            deck.words = (deck.words ?? []) + [word]
            word.ensureCard()
        }
    }

    private static func emoji(for language: String) -> String {
        switch language.prefix(2) {
        case "de": return "🇩🇪"
        case "en": return "🇬🇧"
        case "fr": return "🇫🇷"
        case "es": return "🇪🇸"
        case "it": return "🇮🇹"
        default: return "📘"
        }
    }
}
