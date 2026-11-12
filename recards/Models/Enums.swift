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
