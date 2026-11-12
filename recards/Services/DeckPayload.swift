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
    /// Код `PartOfSpeech`. Строка, а не перечисление: неизвестный код в файле
    /// не должен ронять разбор всего файла — он просто отбрасывается.
    var partOfSpeech: String?

    init(
        word: String,
        translations: [String],
        transcription: String? = nil,
        example: String? = nil,
        exampleTranslation: String? = nil,
        partOfSpeech: String? = nil
    ) {
        self.word = word
        self.translations = translations
        self.transcription = transcription
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.partOfSpeech = partOfSpeech
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
            exampleTranslation: cleaned(exampleTranslation),
            partOfSpeech: PartOfSpeech(code: partOfSpeech)?.rawValue
        )
    }
}

/// Ключ для отсева дубликатов: нормализованный текст слова вместе с набором переводов.
///
/// Слова с одинаковым текстом, но разными переводами — разные слова. Так в колоде
/// уживаются совпадающие формы глагола (`will` — «хотеть (ich)» и «хотеть (er/sie/es)»)
/// и омонимы (`die Bank` — «банк» и «скамейка»). Порядок переводов значения не имеет.
nonisolated enum WordKey {
    static func make(text: String, translations: [String]) -> String {
        let normalizedTranslations = Set(translations.map(AnswerChecker.normalize))
            .filter { !$0.isEmpty }
            .sorted()
        // Разделитель — управляющий символ, который не встречается в тексте слов.
        return ([AnswerChecker.normalize(text)] + normalizedTranslations).joined(separator: "\u{1F}")
    }
}
