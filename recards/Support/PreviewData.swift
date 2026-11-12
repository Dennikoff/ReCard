import Foundation
import SwiftData

/// Данные для превью SwiftUI. В сборку приложения влияют только через превью.
@MainActor
enum PreviewData {

    static let container: ModelContainer = {
        let schema = Schema([Deck.self, Word.self, ReCard.self, ReLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])

        let deck = Deck(name: "Немецкий A1", emoji: "🇩🇪", sourceLanguage: "de-DE", targetLanguage: "ru-RU")
        container.mainContext.insert(deck)

        let samples: [(String, [String], String, String, String)] = [
            ("der Hund", ["собака", "пёс"], "/hʊnt/", "Der Hund bellt.", "Собака лает."),
            ("die Katze", ["кошка"], "/ˈkatsə/", "Die Katze schläft.", "Кошка спит."),
            ("das Haus", ["дом"], "/haʊs/", "Das Haus ist groß.", "Дом большой."),
        ]

        for (text, translations, transcription, example, exampleTranslation) in samples {
            let word = Word(
                text: text,
                translations: translations,
                transcription: transcription,
                example: example,
                exampleTranslation: exampleTranslation
            )
            word.deck = deck
            container.mainContext.insert(word)
            deck.words = (deck.words ?? []) + [word]
            word.ensureCard()
        }

        return container
    }()

    static var sampleDeck: Deck {
        let descriptor = FetchDescriptor<Deck>()
        return try! container.mainContext.fetch(descriptor).first!
    }

    static var sampleWord: Word {
        sampleDeck.sortedWords.first!
    }
}
