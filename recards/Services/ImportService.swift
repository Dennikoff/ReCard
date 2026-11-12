import Foundation

/// Причина, по которой строка не попала в колоду.
nonisolated enum SkipReason: String, Equatable, Sendable {
    case malformed
    case emptyWord
    case emptyTranslation
    case duplicateInFile
    case duplicateInDeck

    var localizedDescription: String {
        switch self {
        case .malformed: return "Неразобранная строка"
        case .emptyWord: return "Пустое слово"
        case .emptyTranslation: return "Нет перевода"
        case .duplicateInFile: return "Повтор в файле"
        case .duplicateInDeck: return "Уже есть в колоде"
        }
    }
}

/// Пропущенная строка с указанием причины — показывается в предпросмотре.
nonisolated struct SkippedRow: Equatable, Hashable, Identifiable, Sendable {
    var id: Int { line }
    var line: Int
    var content: String
    var reason: SkipReason
}

/// Результат разбора файла или вставленного текста.
nonisolated struct ImportResult: Equatable, Hashable, Sendable {
    var words: [WordPayload] = []
    var skipped: [SkippedRow] = []
    /// Заполняется только при импорте JSON: файл несёт собственные метаданные колоды.
    var suggestedDeck: DeckPayload?

    var isEmpty: Bool { words.isEmpty }
}

/// Разбор входных данных импорта.
///
/// Формат определяется автоматически: JSON распознаётся по первому непробельному символу,
/// разделитель таблицы — по наличию табуляции в первой строке.
nonisolated enum ImportService {

    /// Разделитель нескольких переводов внутри одной ячейки.
    static let translationSeparator: Character = ";"

    // MARK: - Точка входа

    /// - Parameter existing: ключи `WordKey` слов, уже присутствующих в колоде.
    static func parse(_ input: String, existing: Set<String> = []) -> ImportResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ImportResult() }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return parseJSON(trimmed, existing: existing)
        }
        return parseDelimited(trimmed, existing: existing)
    }

    // MARK: - JSON

    private static func parseJSON(_ input: String, existing: Set<String>) -> ImportResult {
        guard let data = input.data(using: .utf8) else {
            return ImportResult(skipped: [SkippedRow(line: 1, content: "", reason: .malformed)])
        }

        let decoder = JSONDecoder()

        // Файл может быть как целой колодой, так и голым массивом слов.
        let payloads: [WordPayload]
        var suggested: DeckPayload?

        if let deck = try? decoder.decode(DeckPayload.self, from: data) {
            payloads = deck.words
            suggested = deck
        } else if let words = try? decoder.decode([WordPayload].self, from: data) {
            payloads = words
        } else {
            return ImportResult(skipped: [SkippedRow(line: 1, content: "", reason: .malformed)])
        }

        var result = collect(payloads.enumerated().map { ($0.offset + 1, $0.element, "") }, existing: existing)
        result.suggestedDeck = suggested
        return result
    }

    // MARK: - CSV и TSV

    private static func parseDelimited(_ input: String, existing: Set<String>) -> ImportResult {
        let lines = splitRows(input)
        guard !lines.isEmpty else { return ImportResult() }

        let delimiter: Character = lines[0].contains("\t") ? "\t" : ","

        var candidates: [(Int, WordPayload, String)] = []
        var skipped: [SkippedRow] = []

        for (index, line) in lines.enumerated() {
            let number = index + 1
            let raw = line.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { continue }

            let fields = splitFields(line, delimiter: delimiter)

            // Строка заголовка распознаётся по названиям колонок и пропускается молча.
            if index == 0, isHeader(fields) { continue }

            guard fields.count >= 2 else {
                skipped.append(SkippedRow(line: number, content: raw, reason: .malformed))
                continue
            }

            let word = fields[0].trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else {
                skipped.append(SkippedRow(line: number, content: raw, reason: .emptyWord))
                continue
            }

            let translations = fields[1]
                .split(separator: translationSeparator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !translations.isEmpty else {
                skipped.append(SkippedRow(line: number, content: raw, reason: .emptyTranslation))
                continue
            }

            let payload = WordPayload(
                word: word,
                translations: translations,
                transcription: field(fields, at: 2),
                example: field(fields, at: 3),
                exampleTranslation: field(fields, at: 4)
            )
            candidates.append((number, payload, raw))
        }

        var result = collect(candidates, existing: existing)
        result.skipped = (skipped + result.skipped).sorted { $0.line < $1.line }
        return result
    }

    // MARK: - Общая часть

    /// Отсеивает пустые записи и дубликаты, сохраняя порядок следования.
    private static func collect(
        _ candidates: [(Int, WordPayload, String)],
        existing: Set<String>
    ) -> ImportResult {
        var words: [WordPayload] = []
        var skipped: [SkippedRow] = []
        var seen = existing

        for (line, candidate, raw) in candidates {
            let payload = candidate.normalized
            let content = raw.isEmpty ? payload.word : raw

            guard !payload.word.isEmpty else {
                skipped.append(SkippedRow(line: line, content: content, reason: .emptyWord))
                continue
            }
            guard !payload.translations.isEmpty else {
                skipped.append(SkippedRow(line: line, content: content, reason: .emptyTranslation))
                continue
            }

            let key = WordKey.make(text: payload.word, translations: payload.translations)
            guard !seen.contains(key) else {
                let reason: SkipReason = existing.contains(key) ? .duplicateInDeck : .duplicateInFile
                skipped.append(SkippedRow(line: line, content: content, reason: reason))
                continue
            }

            seen.insert(key)
            words.append(payload)
        }

        return ImportResult(words: words, skipped: skipped)
    }

    private static func field(_ fields: [String], at index: Int) -> String? {
        guard fields.indices.contains(index) else { return nil }
        let value = fields[index].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func isHeader(_ fields: [String]) -> Bool {
        guard let first = fields.first?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return false
        }
        return first == "word"
    }

    // MARK: - Разбор по правилам RFC 4180

    /// Делит текст на строки, не разрывая значения внутри кавычек.
    static func splitRows(_ input: String) -> [String] {
        var rows: [String] = []
        var current = ""
        var insideQuotes = false
        var iterator = input.startIndex

        while iterator < input.endIndex {
            let character = input[iterator]

            if character == "\"" {
                // Удвоенная кавычка внутри значения не переключает режим.
                let next = input.index(after: iterator)
                if insideQuotes, next < input.endIndex, input[next] == "\"" {
                    current.append("\"\"")
                    iterator = input.index(after: next)
                    continue
                }
                insideQuotes.toggle()
                current.append(character)
            } else if (character == "\n" || character == "\r"), !insideQuotes {
                if !current.isEmpty { rows.append(current) }
                current = ""
                // Последовательность CRLF считается одним переносом.
                let next = input.index(after: iterator)
                if character == "\r", next < input.endIndex, input[next] == "\n" {
                    iterator = next
                }
            } else {
                current.append(character)
            }

            iterator = input.index(after: iterator)
        }

        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// Делит строку на ячейки, снимая обрамляющие кавычки и разворачивая удвоенные.
    static func splitFields(_ row: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        var iterator = row.startIndex

        while iterator < row.endIndex {
            let character = row[iterator]

            if character == "\"" {
                let next = row.index(after: iterator)
                if insideQuotes, next < row.endIndex, row[next] == "\"" {
                    current.append("\"")
                    iterator = row.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == delimiter, !insideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }

            iterator = row.index(after: iterator)
        }

        fields.append(current)
        return fields
    }
}
