import Foundation

/// Карточка слова, отобранная в сессию. Не зависит от SwiftData.
nonisolated struct SessionCardRef: Equatable, Sendable {
    var cardID: UUID
    var wordID: UUID
}

/// Одно упражнение в очереди сессии: карточка слова и способ проверки.
nonisolated struct SessionItem: Equatable, Identifiable, Sendable {
    let id: UUID
    var cardID: UUID
    var wordID: UUID
    var direction: CardDirection

    init(cardID: UUID, wordID: UUID, direction: CardDirection) {
        self.id = UUID()
        self.cardID = cardID
        self.wordID = wordID
        self.direction = direction
    }
}

/// Формирование очереди сессии: отбор, перемешивание и разбиение на блоки.
nonisolated enum SessionBuilder {

    /// Раскладывает слова по блокам и превращает каждое в упражнения.
    ///
    /// Все упражнения одного слова попадают в один блок: у слова одна карточка,
    /// и её оценка складывается из всех упражнений. Внутри блока сначала идут все
    /// упражнения первого направления, потом второго — в том порядке, в котором они
    /// перечислены в `CardDirection`. Печать идёт раньше выбора, поэтому слово,
    /// показанное в выборе, уже не подсказывает ответ при печати.
    ///
    /// - Parameters:
    ///   - cards: карточки-кандидаты в произвольном порядке.
    ///   - directions: какими упражнениями проверяется каждое слово.
    ///   - blockSize: максимальное число слов в блоке.
    ///   - limit: дневной лимит, ограничивающий общее число слов.
    ///   - generator: источник случайности; передаётся явно ради воспроизводимости тестов.
    static func buildBlocks<G: RandomNumberGenerator>(
        from cards: [SessionCardRef],
        directions: [CardDirection],
        blockSize: Int,
        limit: Int,
        using generator: inout G
    ) -> [[SessionItem]] {
        guard blockSize > 0, limit > 0 else { return [] }

        let ordered = CardDirection.allCases.filter(directions.contains)
        guard !ordered.isEmpty else { return [] }

        let selected = Array(cards.shuffled(using: &generator).prefix(limit))

        return stride(from: 0, to: selected.count, by: blockSize).map { start in
            let chunk = selected[start..<min(start + blockSize, selected.count)]
            return ordered.flatMap { direction in
                chunk.shuffled(using: &generator).map {
                    SessionItem(cardID: $0.cardID, wordID: $0.wordID, direction: direction)
                }
            }
        }
    }

    /// Вариант с системным источником случайности.
    static func buildBlocks(
        from cards: [SessionCardRef],
        directions: [CardDirection],
        blockSize: Int,
        limit: Int
    ) -> [[SessionItem]] {
        var generator = SystemRandomNumberGenerator()
        return buildBlocks(
            from: cards, directions: directions, blockSize: blockSize, limit: limit, using: &generator
        )
    }
}
