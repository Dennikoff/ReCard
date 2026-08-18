import Foundation

/// Слово в файловом представлении.
///
/// Один и тот же тип используется для импорта, экспорта, резервной копии
/// и демо-колод из бандла.
nonisolated struct WordPayload: Codable, Equatable, Hashable, Sendable {
    var word: String
    var translations: [String]
    var transcription: String?
    var example: String?
    var exampleTranslation: String?

    init(
        word: String,
        translations: [String],
        transcription: String? = nil,
        example: String? = nil,
        exampleTranslation: String? = nil
    ) {
        self.word = word
        self.translations = translations
        self.transcription = transcription
        self.example = example
        self.exampleTranslation = exampleTranslation
    }
}

/// Колода в файловом представлении.
nonisolated struct DeckPayload: Codable, Equatable, Hashable, Sendable {
    var name: String
    var sourceLanguage: String
    var targetLanguage: String
    var words: [WordPayload]

    init(name: String, sourceLanguage: String, targetLanguage: String, words: [WordPayload]) {
        self.name = name
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.words = words
    }
}

nonisolated extension WordPayload {
    /// Пустые строки в необязательных полях приравниваются к отсутствию значения.
    var normalized: WordPayload {
        func cleaned(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return trimmed
        }

        return WordPayload(
            word: word.trimmingCharacters(in: .whitespacesAndNewlines),
            translations: translations
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            transcription: cleaned(transcription),
            example: cleaned(example),
            exampleTranslation: cleaned(exampleTranslation)
        )
    }
}
