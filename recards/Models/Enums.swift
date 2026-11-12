import Foundation

/// Направление упражнения. У слова одна карточка с одним состоянием планировщика,
/// а направление описывает, каким упражнением её проверяют. Карточка слова всегда
/// хранится как `production`; `recognition` встречается только в упражнениях и журнале.
nonisolated enum CardDirection: String, Codable, CaseIterable, Sendable {
    /// Перевод → слово. Ответ вводится с клавиатуры.
    case production
    /// Слово → перевод. Ответ выбирается из четырёх вариантов.
    case recognition
}

/// Часть речи слова. Нужна только для подбора отвлекающих вариантов в режиме выбора:
/// к существительному — существительные, к глаголу — глаголы.
///
/// Сырые значения — коды в файлах импорта и экспорта.
nonisolated enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun
    case verb
    case adjective
    case other

    /// Название для интерфейса.
    var title: LocalizedStringResource {
        switch self {
        case .noun: return "Существительное"
        case .verb: return "Глагол"
        case .adjective: return "Прилагательное"
        case .other: return "Другое"
        }
    }

    /// Разбирает код из файла: регистр и пробелы не важны, неизвестный код — `nil`.
    init?(code: String?) {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let value = PartOfSpeech(rawValue: code) else { return nil }
        self = value
    }
}

/// Состояние карточки в терминах интервального повторения.
///
/// Дублирует `FSRS.CardState`, чтобы типы пакета не протекали за пределы `FSRSScheduler`.
nonisolated enum ReCardState: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case review
    case relearning
}

/// Оценка ответа, передаваемая планировщику.
///
/// Дублирует `FSRS.Rating` без случая `manual`, который приложение не использует.
nonisolated enum ReRating: Int, Codable, CaseIterable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

/// Результат сравнения введённого ответа с ожидаемым.
nonisolated enum AnswerVerdict: Equatable, Sendable {
    /// Полное совпадение после нормализации.
    case correct
    /// Отличие в один символ — засчитывается, но понижает оценку.
    case correctWithTypo
    case incorrect
}
