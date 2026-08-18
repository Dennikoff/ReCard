import Foundation

/// Элемент очереди сессии, не зависящий от SwiftData.
nonisolated struct SessionItem: Equatable, Identifiable, Sendable {
    var id: UUID
    var wordID: UUID
    var direction: CardDirection

    init(cardID: UUID, wordID: UUID, direction: CardDirection) {
        self.id = cardID
        self.wordID = wordID
        self.direction = direction
    }

    var cardID: UUID { id }
}

/// Формирование очереди сессии: отбор, перемешивание и разбиение на блоки.
nonisolated enum SessionBuilder {

    /// Разбивает карточки на блоки с соблюдением правила о парных карточках.
    ///
    /// Прямая и обратная карточки одного слова никогда не попадают в один блок:
    /// иначе вторая из них становится бесплатной подсказкой к первой.
    ///
    /// - Parameters:
    ///   - items: карточки-кандидаты в произвольном порядке.
    ///   - blockSize: максимальный размер блока.
    ///   - limit: дневной лимит, ограничивающий общее число карточек.
    ///   - generator: источник случайности; передаётся явно ради воспроизводимости тестов.
    static func buildBlocks<G: RandomNumberGenerator>(
        from items: [SessionItem],
        blockSize: Int,
        limit: Int,
        using generator: inout G
    ) -> [[SessionItem]] {
        guard blockSize > 0, limit > 0 else { return [] }

        let selected = Array(items.shuffled(using: &generator).prefix(limit))
        guard !selected.isEmpty else { return [] }

        var blocks: [[SessionItem]] = []
        var wordsInBlock: [Set<UUID>] = []

        for item in selected {
            // Первый блок, где есть место и ещё нет другой карточки того же слова.
            let index = blocks.indices.first { index in
                blocks[index].count < blockSize && !wordsInBlock[index].contains(item.wordID)
            }

            if let index {
                blocks[index].append(item)
                wordsInBlock[index].insert(item.wordID)
            } else {
                blocks.append([item])
                wordsInBlock.append([item.wordID])
            }
        }

        return blocks
    }

    /// Вариант с системным источником случайности.
    static func buildBlocks(
        from items: [SessionItem],
        blockSize: Int,
        limit: Int
    ) -> [[SessionItem]] {
        var generator = SystemRandomNumberGenerator()
        return buildBlocks(from: items, blockSize: blockSize, limit: limit, using: &generator)
    }
}
