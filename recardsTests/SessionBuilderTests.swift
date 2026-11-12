import Testing
import Foundation
@testable import recards

/// Генератор с фиксированным зерном: перемешивание должно быть воспроизводимым,
/// иначе тесты на порядок упражнений будут мигать.
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

    private let both = CardDirection.allCases

    private func makeCards(_ count: Int) -> [SessionCardRef] {
        (0..<count).map { _ in SessionCardRef(cardID: UUID(), wordID: UUID()) }
    }

    @Test("Все упражнения слова попадают в один блок")
    func exercisesOfWordShareBlock() {
        var generator = SeededGenerator(seed: 42)
        let blocks = SessionBuilder.buildBlocks(
            from: makeCards(30), directions: both, blockSize: 8, limit: 100, using: &generator
        )

        var blockOfWord: [UUID: Int] = [:]
        for (index, block) in blocks.enumerated() {
            for item in block {
                let previous = blockOfWord.updateValue(index, forKey: item.wordID)
                #expect(previous == nil || previous == index, "Упражнения слова разнесены по блокам")
            }
        }
    }

    @Test("Пять слов с двумя упражнениями — один блок из десяти")
    func fiveWordsMakeOneBlock() {
        var generator = SeededGenerator(seed: 3)
        let blocks = SessionBuilder.buildBlocks(
            from: makeCards(5), directions: both, blockSize: 20, limit: 50, using: &generator
        )

        #expect(blocks.count == 1)
        #expect(blocks.first?.count == 10)
    }

    @Test("В блоке печать идёт раньше выбора", arguments: [1, 7, 42, 1000, 65_535] as [UInt64])
    func productionComesFirst(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let blocks = SessionBuilder.buildBlocks(
            // Порядок направлений на входе не важен.
            from: makeCards(25), directions: [.recognition, .production], blockSize: 10, limit: 100,
            using: &generator
        )

        for block in blocks {
            let directions = block.map(\.direction)
            let firstRecognition = directions.firstIndex(of: .recognition) ?? directions.count
            #expect(directions[firstRecognition...].allSatisfy { $0 == .recognition })
            #expect(directions.count(where: { $0 == .production }) == directions.count / 2)
        }
    }

    @Test("Каждое слово получает ровно одно упражнение каждого направления")
    func everyWordGetsEachDirectionOnce() {
        var generator = SeededGenerator(seed: 99)
        let cards = makeCards(15)
        let items = SessionBuilder.buildBlocks(
            from: cards, directions: both, blockSize: 8, limit: 100, using: &generator
        ).flatMap { $0 }

        #expect(items.count == cards.count * 2)
        for card in cards {
            let directions = items.filter { $0.cardID == card.cardID }.map(\.direction)
            #expect(Set(directions) == Set(both))
            #expect(directions.count == 2)
        }
        #expect(Set(items.map(\.id)).count == items.count, "У упражнений уникальные идентификаторы")
    }

    @Test("Размер блока считается в словах")
    func blockSizeCountsWords() {
        var generator = SeededGenerator(seed: 7)
        let blocks = SessionBuilder.buildBlocks(
            from: makeCards(40), directions: both, blockSize: 20, limit: 100, using: &generator
        )

        #expect(blocks.count == 2)
        for block in blocks {
            #expect(Set(block.map(\.wordID)).count == 20)
        }
    }

    @Test("Дневной лимит ограничивает число слов")
    func limitCapsWordCount() {
        var generator = SeededGenerator(seed: 7)
        let items = SessionBuilder.buildBlocks(
            from: makeCards(100), directions: both, blockSize: 20, limit: 50, using: &generator
        ).flatMap { $0 }

        #expect(Set(items.map(\.wordID)).count == 50)
    }

    @Test("Без обратного режима — только печать")
    func productionOnly() {
        var generator = SeededGenerator(seed: 5)
        let blocks = SessionBuilder.buildBlocks(
            from: makeCards(25), directions: [.production], blockSize: 20, limit: 100, using: &generator
        )

        #expect(blocks.map(\.count) == [20, 5])
        #expect(blocks.flatMap { $0 }.allSatisfy { $0.direction == .production })
    }

    @Test("Пустой вход даёт пустой результат")
    func emptyInputProducesNoBlocks() {
        var generator = SeededGenerator(seed: 1)
        #expect(SessionBuilder.buildBlocks(
            from: [], directions: both, blockSize: 20, limit: 50, using: &generator
        ).isEmpty)
    }

    @Test("Вырожденные параметры не приводят к бесконечному циклу")
    func degenerateParametersAreSafe() {
        var generator = SeededGenerator(seed: 1)
        let cards = makeCards(5)

        #expect(SessionBuilder.buildBlocks(from: cards, directions: both, blockSize: 0, limit: 50, using: &generator).isEmpty)
        #expect(SessionBuilder.buildBlocks(from: cards, directions: both, blockSize: 20, limit: 0, using: &generator).isEmpty)
        #expect(SessionBuilder.buildBlocks(from: cards, directions: [], blockSize: 20, limit: 50, using: &generator).isEmpty)
    }
}
