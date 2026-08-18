import Testing
import Foundation
@testable import recards

/// Генератор с фиксированным зерном: перемешивание должно быть воспроизводимым,
/// иначе тест на разнесение парных карточек будет мигать.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

@Suite("Формирование блоков сессии")
struct SessionBuilderTests {

    /// Создаёт пары карточек для указанного числа слов.
    private func makeItems(wordCount: Int, directions: [CardDirection] = CardDirection.allCases) -> [SessionItem] {
        (0..<wordCount).flatMap { _ -> [SessionItem] in
            let wordID = UUID()
            return directions.map { SessionItem(cardID: UUID(), wordID: wordID, direction: $0) }
        }
    }

    @Test("Парные карточки одного слова не попадают в один блок")
    func pairedCardsAreSeparated() {
        var generator = SeededGenerator(seed: 42)
        let items = makeItems(wordCount: 30)

        let blocks = SessionBuilder.buildBlocks(
            from: items, blockSize: 20, limit: 100, using: &generator
        )

        for block in blocks {
            let wordIDs = block.map(\.wordID)
            #expect(Set(wordIDs).count == wordIDs.count, "В блоке оказались две карточки одного слова")
        }
    }

    @Test("Правило соблюдается на разных зёрнах", arguments: [1, 7, 42, 1000, 65_535] as [UInt64])
    func pairedCardsAreSeparatedForAnySeed(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let items = makeItems(wordCount: 25)

        let blocks = SessionBuilder.buildBlocks(
            from: items, blockSize: 10, limit: 100, using: &generator
        )

        for block in blocks {
            #expect(Set(block.map(\.wordID)).count == block.count)
        }
    }

    @Test("Размер блока не превышается")
    func blockSizeIsRespected() {
        var generator = SeededGenerator(seed: 7)
        let blocks = SessionBuilder.buildBlocks(
            from: makeItems(wordCount: 40), blockSize: 20, limit: 100, using: &generator
        )

        for block in blocks {
            #expect(block.count <= 20)
        }
    }

    @Test("Дневной лимит ограничивает общее число карточек")
    func limitCapsTotalCount() {
        var generator = SeededGenerator(seed: 7)
        let blocks = SessionBuilder.buildBlocks(
            from: makeItems(wordCount: 100), blockSize: 20, limit: 50, using: &generator
        )

        #expect(blocks.flatMap { $0 }.count == 50)
    }

    @Test("Ни одна карточка не теряется и не дублируется")
    func everySelectedCardAppearsOnce() {
        var generator = SeededGenerator(seed: 99)
        let items = makeItems(wordCount: 15)

        let blocks = SessionBuilder.buildBlocks(
            from: items, blockSize: 8, limit: 100, using: &generator
        )
        let flattened = blocks.flatMap { $0 }

        #expect(flattened.count == items.count)
        #expect(Set(flattened.map(\.cardID)).count == items.count)
    }

    @Test("Пустой вход даёт пустой результат")
    func emptyInputProducesNoBlocks() {
        var generator = SeededGenerator(seed: 1)
        #expect(SessionBuilder.buildBlocks(from: [], blockSize: 20, limit: 50, using: &generator).isEmpty)
    }

    @Test("Нулевые размер блока и лимит не приводят к бесконечному циклу")
    func degenerateParametersAreSafe() {
        var generator = SeededGenerator(seed: 1)
        let items = makeItems(wordCount: 5)

        #expect(SessionBuilder.buildBlocks(from: items, blockSize: 0, limit: 50, using: &generator).isEmpty)
        #expect(SessionBuilder.buildBlocks(from: items, blockSize: 20, limit: 0, using: &generator).isEmpty)
    }

    @Test("Одиночные карточки без пар помещаются в блоки целиком")
    func unpairedCardsFillBlocks() {
        var generator = SeededGenerator(seed: 5)
        let items = makeItems(wordCount: 25, directions: [.production])

        let blocks = SessionBuilder.buildBlocks(
            from: items, blockSize: 20, limit: 100, using: &generator
        )

        #expect(blocks.count == 2)
        #expect(blocks[0].count == 20)
        #expect(blocks[1].count == 5)
    }
}
