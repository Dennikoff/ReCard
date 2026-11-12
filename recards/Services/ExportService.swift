import Foundation

/// Выгрузка колод в файл.
///
/// Формат совпадает с форматом импорта, поэтому выгруженный файл можно загрузить обратно
/// без потерь. Поскольку синхронизации в версии 1.0 нет, экспорт — единственная защита
/// пользователя от потери прогресса.
nonisolated enum ExportService {

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeJSON(_ payload: DeckPayload) throws -> Data {
        try encoder.encode(payload)
    }

    static func makeJSON(_ payloads: [DeckPayload]) throws -> Data {
        try encoder.encode(payloads)
    }

    /// Формирует содержимое CSV по правилам RFC 4180.
    static func makeCSV(_ payload: DeckPayload) -> String {
        var rows = ["word,translation,transcription,example,exampleTranslation,partOfSpeech"]

        for word in payload.words {
            let fields = [
                word.word,
                word.translations.joined(separator: String(ImportService.translationSeparator)),
                word.transcription ?? "",
                word.example ?? "",
                word.exampleTranslation ?? "",
                word.partOfSpeech ?? "",
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    /// Значения с запятой, кавычкой или переносом строки обрамляются кавычками,
    /// внутренние кавычки удваиваются.
    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Имя файла, пригодное для файловой системы.
    static func fileName(for deckName: String, extension ext: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let sanitized = deckName.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespaces)
        let base = sanitized.isEmpty ? "deck" : sanitized
        return "\(base).\(ext)"
    }
}
