import Testing
@testable import recards

@Suite("Нормализация ответа")
struct AnswerNormalizationTests {

    @Test("Регистр не влияет на сравнение")
    func caseIsIgnored() {
        #expect(AnswerChecker.normalize("Hund") == AnswerChecker.normalize("hund"))
        #expect(AnswerChecker.check(input: "hund", against: ["der Hund"]) == .incorrect)
        #expect(AnswerChecker.check(input: "der hund", against: ["der Hund"]) == .correct)
    }

    @Test("Пробелы по краям и внутри схлопываются")
    func whitespaceIsCollapsed() {
        #expect(AnswerChecker.check(input: "  der   Hund  ", against: ["der Hund"]) == .correct)
        #expect(AnswerChecker.check(input: "der\nHund", against: ["der Hund"]) == .correct)
    }

    @Test("Умлауты принимаются в обоих написаниях")
    func umlautsAreInterchangeable() {
        #expect(AnswerChecker.check(input: "über", against: ["über"]) == .correct)
        #expect(AnswerChecker.check(input: "ueber", against: ["über"]) == .correct)
        #expect(AnswerChecker.check(input: "über", against: ["ueber"]) == .correct)
        #expect(AnswerChecker.check(input: "Mädchen", against: ["maedchen"]) == .correct)
    }

    @Test("Эсцет приравнивается к двойному s")
    func eszettIsInterchangeable() {
        #expect(AnswerChecker.check(input: "fuss", against: ["Fuß"]) == .correct)
        #expect(AnswerChecker.check(input: "Fuß", against: ["fuss"]) == .correct)
    }

    @Test("Буква ё приравнивается к е")
    func yoIsInterchangeable() {
        #expect(AnswerChecker.check(input: "ежик", against: ["ёжик"]) == .correct)
        #expect(AnswerChecker.check(input: "ёжик", against: ["ежик"]) == .correct)
    }
}

@Suite("Проверка ответа")
struct AnswerCheckTests {

    @Test("Засчитывается любой из переводов")
    func anyTranslationCounts() {
        let expected = ["собака", "пёс"]
        #expect(AnswerChecker.check(input: "собака", against: expected) == .correct)
        #expect(AnswerChecker.check(input: "пес", against: expected) == .correct)
        #expect(AnswerChecker.check(input: "кошка", against: expected) == .incorrect)
    }

    @Test("Одна опечатка прощается на словах от четырёх букв")
    func singleTypoIsForgiven() {
        #expect(AnswerChecker.check(input: "hunher", against: ["hunger"]) == .correctWithTypo)
        #expect(AnswerChecker.check(input: "hunge", against: ["hunger"]) == .correctWithTypo)
        #expect(AnswerChecker.check(input: "hungerr", against: ["hunger"]) == .correctWithTypo)
    }

    @Test("Перестановка соседних букв считается одной опечаткой")
    func transpositionIsOneTypo() {
        // Обычное расстояние Левенштейна дало бы здесь 2 и не засчитало бы ответ,
        // хотя это самая частая описка при быстром наборе.
        #expect(AnswerChecker.check(input: "hnuger", against: ["hunger"]) == .correctWithTypo)
        #expect(AnswerChecker.check(input: "biespiel", against: ["beispiel"]) == .correctWithTypo)
    }

    @Test("На коротких словах опечатка не прощается")
    func shortWordsAreStrict() {
        #expect(AnswerChecker.check(input: "tag", against: ["tal"]) == .incorrect)
        #expect(AnswerChecker.check(input: "das", against: ["dax"]) == .incorrect)
    }

    @Test("Отличие больше чем на один символ не засчитывается")
    func twoErrorsFail() {
        #expect(AnswerChecker.check(input: "hnugre", against: ["hunger"]) == .incorrect)
    }

    @Test("Пустой ввод неверен всегда")
    func emptyInputIsIncorrect() {
        #expect(AnswerChecker.check(input: "", against: ["hunger"]) == .incorrect)
        #expect(AnswerChecker.check(input: "   ", against: ["hunger"]) == .incorrect)
    }

    @Test("Пустой список ожидаемых ответов не засчитывается")
    func emptyExpectationIsIncorrect() {
        #expect(AnswerChecker.check(input: "hunger", against: []) == .incorrect)
        #expect(AnswerChecker.check(input: "hunger", against: [""]) == .incorrect)
    }

    @Test("Пропущенный артикль считается ошибкой, а не опечаткой")
    func missingArticleIsAnError() {
        // Артикль является частью строки, отдельной логики для него нет,
        // поэтому расстояние в четыре символа даёт обычную ошибку.
        #expect(AnswerChecker.check(input: "Hund", against: ["der Hund"]) == .incorrect)
    }

    @Test("Точное совпадение выигрывает у совпадения с опечаткой")
    func exactMatchWinsOverTypo() {
        // "wagen" отличается от "wagon" на один символ, но точное совпадение есть в списке.
        #expect(AnswerChecker.check(input: "wagen", against: ["wagon", "wagen"]) == .correct)
    }
}

@Suite("Формы слова — не опечатки")
struct KnownWordTests {

    /// Колода с полным спряжением `machen`, как в демо-колоде.
    private let deck = AnswerChecker.knownWordSet(["machen", "mache", "machst", "macht", "macht", "machen"])

    private func check(_ input: String, expecting expected: String) -> AnswerVerdict {
        AnswerChecker.check(input: input, against: [expected], knownWords: deck)
    }

    @Test("Другая форма из колоды — ошибка, а не опечатка")
    func otherFormIsIncorrect() {
        #expect(check("machst", expecting: "macht") == .incorrect)
        #expect(check("mache", expecting: "macht") == .incorrect)
        #expect(check("machen", expecting: "mache") == .incorrect)
        #expect(check("macht", expecting: "mache") == .incorrect)
        #expect(check("macht", expecting: "machst") == .incorrect)
        #expect(check("mache", expecting: "machen") == .incorrect)
    }

    @Test("Настоящие опечатки по-прежнему прощаются")
    func realTyposAreForgiven() {
        #expect(check("mahct", expecting: "macht") == .correctWithTypo)
        #expect(check("machr", expecting: "macht") == .correctWithTypo)
        #expect(check("machp", expecting: "mache") == .correctWithTypo)
        #expect(check("machn", expecting: "machen") == .correctWithTypo)
    }

    @Test("Точный ответ верен, даже если такой же текст есть у другого слова")
    func exactAnswerWinsOverKnownWord() {
        // `macht` есть в колоде дважды (er и ihr) — это не мешает верному ответу.
        #expect(check("macht", expecting: "macht") == .correct)
        #expect(check("Macht", expecting: "macht") == .correct)
    }

    @Test("Умлаут: форма другого лица не прощается")
    func umlautFormIsIncorrect() {
        let fahren = AnswerChecker.knownWordSet(["fahren", "fahre", "fährst", "fährt", "fahrt"])
        #expect(AnswerChecker.check(input: "fahrt", against: ["fährt"], knownWords: fahren) == .incorrect)
        #expect(AnswerChecker.check(input: "faehrt", against: ["fährt"], knownWords: fahren) == .correct)
    }

    @Test("Без колоды поведение прежнее")
    func emptyKnownWordsKeepsOldBehavior() {
        #expect(AnswerChecker.check(input: "machst", against: ["macht"]) == .correctWithTypo)
    }
}

@Suite("Расстояние между строками")
struct LevenshteinTests {

    @Test("Перестановка стоит одну операцию")
    func transpositionCostsOne() {
        #expect(AnswerChecker.distance(Array("hnuger"), Array("hunger")) == 1)
        #expect(AnswerChecker.distance(Array("ab"), Array("ba")) == 1)
    }

    @Test("Базовые случаи")
    func basics() {
        #expect(AnswerChecker.distance(Array("kitten"), Array("sitting")) == 3)
        #expect(AnswerChecker.distance(Array("hund"), Array("hund")) == 0)
        #expect(AnswerChecker.distance(Array(""), Array("hund")) == 4)
        #expect(AnswerChecker.distance(Array("hund"), Array("")) == 4)
        #expect(AnswerChecker.distance(Array(""), Array("")) == 0)
    }

    @Test("Расстояние симметрично")
    func isSymmetric() {
        let a = Array("beispiel")
        let b = Array("beispel")
        #expect(AnswerChecker.distance(a, b) == AnswerChecker.distance(b, a))
    }
}
