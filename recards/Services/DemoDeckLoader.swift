import Foundation
import SwiftData

/// Загрузка демо-колод из бандла при первом запуске.
///
/// Колоды ничем не отличаются от пользовательских: их можно править и удалять.
/// Они же служат тестовыми данными при разработке.
@MainActor
enum DemoDeckLoader {

    private static let hasLoadedKey = "demoDecks.loaded"
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
                exampleTranslation: normalized.exampleTranslation
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
