import Testing
import Foundation
@testable import recards

@Suite("Разбор CSV")
struct CSVImportTests {

    @Test("Простой файл с заголовком")
    func basicFile() {
        let input = """
        word,translation,transcription,example,exampleTranslation
        der Hund,собака,/hʊnt/,Der Hund bellt.,Собака лает.
        die Katze,кошка,/ˈkatsə/,,
        """

        let result = ImportService.parse(input)

        #expect(result.words.count == 2)
        #expect(result.skipped.isEmpty)
        #expect(result.words[0].word == "der Hund")
        #expect(result.words[0].translations == ["собака"])
        #expect(result.words[0].transcription == "/hʊnt/")
        #expect(result.words[0].example == "Der Hund bellt.")
        // Пустые хвостовые поля становятся отсутствующими значениями.
        #expect(result.words[1].example == nil)
        #expect(result.words[1].exampleTranslation == nil)
    }

    @Test("Обязательны только первые две колонки")
    func minimalColumns() {
        let result = ImportService.parse("der Hund,собака")

        #expect(result.words.count == 1)
        #expect(result.words[0].transcription == nil)
    }

    @Test("Несколько переводов разделяются точкой с запятой")
    func multipleTranslations() {
        let result = ImportService.parse("der Hund,собака; пёс ;пёсик")

        #expect(result.words[0].translations == ["собака", "пёс", "пёсик"])
    }

    @Test("Запятая внутри кавычек не делит ячейку")
    func quotedComma() {
        let result = ImportService.parse("""
        word,translation,transcription,example,exampleTranslation
        "guten Tag, mein Freund",привет,,,
        """)

        #expect(result.words.count == 1)
        #expect(result.words[0].word == "guten Tag, mein Freund")
    }

    @Test("Удвоенная кавычка разворачивается в одну")
    func escapedQuote() {
        // Расширенный делимитер: содержимое само содержит три кавычки подряд.
        let result = ImportService.parse(#"""
        word,translation
        "say ""hallo""",сказать привет
        """#)

        #expect(result.words[0].word == #"say "hallo""#)
    }

    @Test("Перенос строки внутри кавычек не разрывает запись")
    func newlineInsideQuotes() {
        let result = ImportService.parse("""
        word,translation,transcription,example
        der Hund,собака,,"Der Hund bellt.
        Er ist laut."
        """)

        #expect(result.words.count == 1)
        #expect(result.words[0].example?.contains("\n") == true)
    }

    @Test("Табуляция распознаётся как разделитель")
    func tabSeparatedIsDetected() {
        let result = ImportService.parse("der Hund\tсобака\t/hʊnt/")

        #expect(result.words.count == 1)
        #expect(result.words[0].word == "der Hund")
        #expect(result.words[0].transcription == "/hʊnt/")
    }

    @Test("Заголовок распознаётся и не считается словом")
    func headerIsSkipped() {
        let withHeader = ImportService.parse("word,translation\nder Hund,собака")
        let withoutHeader = ImportService.parse("der Hund,собака")

        #expect(withHeader.words.count == 1)
        #expect(withoutHeader.words.count == 1)
        #expect(withHeader.skipped.isEmpty)
    }

    @Test("Строка без перевода пропускается с указанием причины")
    func rowWithoutTranslationIsSkipped() {
        let result = ImportService.parse("""
        der Hund,собака
        die Katze
        das Haus,
        """)

        #expect(result.words.count == 1)
        #expect(result.skipped.count == 2)
        #expect(result.skipped[0].reason == .malformed)
        #expect(result.skipped[1].reason == .emptyTranslation)
    }

    @Test("Строка без слова пропускается")
    func rowWithoutWordIsSkipped() {
        let result = ImportService.parse(",собака")

        #expect(result.words.isEmpty)
        #expect(result.skipped.first?.reason == .emptyWord)
    }

    @Test("Пустые строки просто игнорируются")
    func blankLinesAreIgnored() {
        let result = ImportService.parse("der Hund,собака\n\n\ndie Katze,кошка")

        #expect(result.words.count == 2)
        #expect(result.skipped.isEmpty)
    }

    @Test("Номера пропущенных строк соответствуют файлу")
    func skippedLineNumbersAreAccurate() {
        let result = ImportService.parse("""
        word,translation
        der Hund,собака
        сломанная строка
        die Katze,кошка
        """)

        #expect(result.skipped.count == 1)
        #expect(result.skipped[0].line == 3)
    }
}

@Suite("Дубликаты при импорте")
struct ImportDuplicateTests {

    @Test("Повтор внутри файла пропускается")
    func duplicateInFile() {
        let result = ImportService.parse("der Hund,собака\nder Hund,собака")

        #expect(result.words.count == 1)
        #expect(result.skipped.count == 1)
        #expect(result.skipped[0].reason == .duplicateInFile)
    }

    @Test("Слово, уже имеющееся в колоде, пропускается")
    func duplicateInDeck() {
        let existing: Set<String> = [WordKey.make(text: "der Hund", translations: ["собака"])]
        let result = ImportService.parse("der Hund,собака\ndie Katze,кошка", existing: existing)

        #expect(result.words.count == 1)
        #expect(result.words[0].word == "die Katze")
        #expect(result.skipped[0].reason == .duplicateInDeck)
    }

    @Test("Дубликаты определяются по тем же правилам, что и проверка ответа")
    func duplicatesUseAnswerNormalization() {
        // Регистр и написание умлаута не должны порождать вторую копию слова.
        let result = ImportService.parse("über,над\nUEBER,НАД")

        #expect(result.words.count == 1)
        #expect(result.skipped[0].reason == .duplicateInFile)
    }

    @Test("Одинаковый текст с разными переводами — разные слова")
    func sameTextDifferentTranslationsIsNotDuplicate() {
        // Совпадающие формы глагола и омонимы должны уживаться в одной колоде.
        let result = ImportService.parse("will,хотеть (ich)\nwill,хотеть (er/sie/es)\ndie Bank,банк\ndie Bank,скамейка")

        #expect(result.words.count == 4)
        #expect(result.skipped.isEmpty)
    }

    @Test("Порядок и регистр переводов не делают слово новым")
    func translationOrderDoesNotMatter() {
        let existing: Set<String> = [WordKey.make(text: "der Hund", translations: ["собака", "пёс"])]
        let result = ImportService.parse("der Hund\tПёс; собака", existing: existing)

        #expect(result.words.isEmpty)
        #expect(result.skipped.first?.reason == .duplicateInDeck)
    }
}

@Suite("Разбор JSON")
struct JSONImportTests {

    @Test("Колода целиком с метаданными")
    func fullDeck() {
        let input = """
        { "name": "Немецкий A1", "sourceLanguage": "de-DE", "targetLanguage": "ru-RU",
          "words": [ { "word": "der Hund", "translations": ["собака", "пёс"],
                       "transcription": "/hʊnt/", "example": "Der Hund bellt.",
                       "exampleTranslation": "Собака лает." } ] }
        """

        let result = ImportService.parse(input)

        #expect(result.words.count == 1)
        #expect(result.words[0].translations == ["собака", "пёс"])
        #expect(result.suggestedDeck?.name == "Немецкий A1")
        #expect(result.suggestedDeck?.sourceLanguage == "de-DE")
    }

    @Test("Голый массив слов принимается без метаданных колоды")
    func bareWordArray() {
        let input = """
        [ { "word": "der Hund", "translations": ["собака"] } ]
        """

        let result = ImportService.parse(input)

        #expect(result.words.count == 1)
        #expect(result.suggestedDeck == nil)
    }

    @Test("Испорченный JSON даёт понятную ошибку, а не падение")
    func brokenJSON() {
        let result = ImportService.parse("{ \"name\": ")

        #expect(result.words.isEmpty)
        #expect(result.skipped.first?.reason == .malformed)
    }

    @Test("Слово без перевода пропускается и в JSON")
    func jsonWordWithoutTranslation() {
        let result = ImportService.parse("""
        [ { "word": "der Hund", "translations": [] },
          { "word": "die Katze", "translations": ["кошка"] } ]
        """)

        #expect(result.words.count == 1)
        #expect(result.skipped.first?.reason == .emptyTranslation)
    }
}

@Suite("Экспорт")
struct ExportServiceTests {

    private let payload = DeckPayload(
        name: "Тест",
        sourceLanguage: "de-DE",
        targetLanguage: "ru-RU",
        words: [
            WordPayload(
                word: "der Hund",
                translations: ["собака", "пёс"],
                transcription: "/hʊnt/",
                example: "Der Hund bellt.",
                exampleTranslation: "Собака лает.",
                partOfSpeech: "noun"
            ),
            WordPayload(word: "liest", translations: ["читать (du)"], partOfSpeech: "verb"),
        ]
    )

    @Test("Выгруженный JSON загружается обратно без потерь")
    func jsonRoundTrip() throws {
        let data = try ExportService.makeJSON(payload)
        let text = String(decoding: data, as: UTF8.self)
        let result = ImportService.parse(text)

        #expect(result.words == payload.words)
        #expect(result.suggestedDeck == payload)
    }

    @Test("Выгруженный CSV загружается обратно без потерь")
    func csvRoundTrip() {
        let csv = ExportService.makeCSV(payload)
        let result = ImportService.parse(csv)

        #expect(result.words == payload.words)
    }

    @Test("Значения с запятыми и кавычками переживают выгрузку")
    func csvEscaping() {
        let tricky = DeckPayload(
            name: "Тест",
            sourceLanguage: "de-DE",
            targetLanguage: "ru-RU",
            words: [
                WordPayload(
                    word: "guten Tag, Freund",
                    translations: ["привет"],
                    example: "Er sagt \"hallo\"."
                ),
            ]
        )

        let result = ImportService.parse(ExportService.makeCSV(tricky))

        #expect(result.words == tricky.words)
    }

    @Test("Имя файла очищается от недопустимых символов")
    func fileNameIsSanitized() {
        #expect(ExportService.fileName(for: "Немецкий A1", extension: "json") == "Немецкий A1.json")
        #expect(ExportService.fileName(for: "a/b:c", extension: "csv") == "a-b-c.csv")
        #expect(ExportService.fileName(for: "   ", extension: "json") == "deck.json")
    }
}

@Suite("Часть речи в файлах")
struct PartOfSpeechImportTests {

    @Test("Код разбирается без учёта регистра и пробелов, неизвестный отбрасывается")
    func codeParsing() {
        #expect(PartOfSpeech(code: " Verb ") == .verb)
        #expect(PartOfSpeech(code: "noun") == .noun)
        #expect(PartOfSpeech(code: "глагол") == nil)
        #expect(PartOfSpeech(code: "") == nil)
        #expect(PartOfSpeech(code: nil) == nil)
    }

    @Test("Шестая колонка CSV — часть речи")
    func csvColumn() {
        let input = """
        word,translation,transcription,example,exampleTranslation,partOfSpeech
        der Hund,собака,,,,noun
        liest,читать (du),,,,VERB
        gut,хороший,,,,прилагательное
        die Katze,кошка
        """

        let result = ImportService.parse(input)

        #expect(result.words.map(\.partOfSpeech) == ["noun", "verb", nil, nil])
        #expect(result.skipped.isEmpty, "Неизвестный код не повод пропускать слово")
    }

    @Test("Неизвестный код в JSON не ломает разбор файла")
    func jsonUnknownCode() {
        let input = """
        [{"word": "gut", "translations": ["хороший"], "partOfSpeech": "adj"},
         {"word": "gehen", "translations": ["идти"], "partOfSpeech": "verb"}]
        """

        let result = ImportService.parse(input)

        #expect(result.words.map(\.partOfSpeech) == [nil, "verb"])
    }
}
