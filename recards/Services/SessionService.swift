import Foundation
import SwiftData

/// Отбор материала для сессий и подсчёт дневных лимитов.
///
/// Лимиты глобальные, а не по колодам: при лимите на колоду пользователь с тремя
/// колодами получал бы тройную норму новых слов и утонул.
@MainActor
enum SessionService {

    // MARK: - Колоды

    static func activeDecks(in context: ModelContext) -> [Deck] {
        let descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.isActive })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Дневные лимиты

    /// Сколько новых слов уже начато сегодня.
    static func newWordsStartedToday(in context: ModelContext, now: Date = AppClock.now) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        // #Predicate принимает только одно выражение, поэтому вместо `if let`
        // используется подстановка заведомо давней даты. Значение вынесено в переменную:
        // обращение к `Date.distantPast` прямо внутри предиката не компилируется.
        let fallback = Date.distantPast
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate { word in
                (word.startedAt ?? fallback) >= start
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Сколько слов уже повторено сегодня. Первые показы новых слов не считаются.
    ///
    /// Считаются слова, а не записи журнала: на одно повторение слова приходится
    /// по записи на каждое упражнение и на каждую повторную попытку после ошибки.
    static func reviewsDoneToday(in context: ModelContext, now: Date = AppClock.now) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        let newState = ReCardState.new.rawValue
        let descriptor = FetchDescriptor<ReLog>(
            predicate: #Predicate { log in
                log.reviewedAt >= start && log.stateRaw != newState
            }
        )
        let logs = (try? context.fetch(descriptor)) ?? []
        return Set(logs.map(\.wordID)).count
    }

    static func remainingNewWords(in context: ModelContext, now: Date = AppClock.now) -> Int {
        max(0, AppSettings.newWordsPerDay - newWordsStartedToday(in: context, now: now))
    }

    static func remainingReviews(in context: ModelContext, now: Date = AppClock.now) -> Int {
        max(0, AppSettings.reviewsPerDay - reviewsDoneToday(in: context, now: now))
    }

    // MARK: - Материал для сессий

    /// Слова, к изучению которых ещё не приступали.
    ///
    /// - Parameter deck: если задана, берутся слова только из неё; иначе из всех активных.
    static func newWords(in context: ModelContext, deck: Deck? = nil) -> [Word] {
        let decks = deck.map { [$0] } ?? activeDecks(in: context)
        return decks
            .flatMap(\.sortedWords)
            .filter(\.isNew)
    }

    /// Карточки, срок показа которых наступил. Одна карточка — одно слово.
    static func dueCards(in context: ModelContext, deck: Deck? = nil, now: Date = AppClock.now) -> [ReCard] {
        let decks = deck.map { [$0] } ?? activeDecks(in: context)
        return decks
            .flatMap(\.sortedWords)
            .filter { !$0.isNew }
            .compactMap(\.card)
            .filter { !$0.isArchived && $0.due <= now }
            .sorted { $0.due < $1.due }
    }

    /// Упражнения, которыми проверяется каждое слово при повторении.
    static var reviewDirections: [CardDirection] {
        AppSettings.recognitionEnabled ? [.production, .recognition] : [.production]
    }

    /// Ближайший срок показа среди неархивированных карточек — для подсказки «приходи через N часов».
    static func nextDueDate(in context: ModelContext, now: Date = AppClock.now) -> Date? {
        activeDecks(in: context)
            .flatMap(\.sortedWords)
            .compactMap(\.card)
            .filter { !$0.isArchived && $0.due > now }
            .map(\.due)
            .min()
    }

    // MARK: - Сводка для главного экрана

    struct Summary {
        var newAvailable: Int
        var dueNow: Int
        var learned: Int
        var hasDecks: Bool
        var nextDue: Date?

        var canLearn: Bool { newAvailable > 0 }
        var canReview: Bool { dueNow > 0 }
    }

    static func summary(in context: ModelContext, now: Date = AppClock.now) -> Summary {
        let decks = activeDecks(in: context)
        let words = decks.flatMap(\.sortedWords)

        let available = min(
            words.count(where: \.isNew),
            remainingNewWords(in: context, now: now)
        )
        let due = min(
            dueCards(in: context, now: now).count,
            remainingReviews(in: context, now: now)
        )

        return Summary(
            newAvailable: available,
            dueNow: due,
            learned: words.count(where: \.isLearned),
            hasDecks: !decks.isEmpty,
            nextDue: nextDueDate(in: context, now: now)
        )
    }

    // MARK: - Отвлекающие варианты

    /// Переводы, которые засчитываются в режиме выбора: свои и всех слов колоды
    /// с тем же текстом. Совпадающие формы (`will` для ich и для er/sie/es) на экране
    /// неотличимы, поэтому верен перевод любой из них — среди вариантов их может быть два.
    static func acceptedTranslations(for word: Word) -> [String] {
        let key = AnswerChecker.normalize(word.text)
        let twins = (word.deck?.words ?? []).filter {
            $0.id != word.id && AnswerChecker.normalize($0.text) == key
        }
        return word.translations + twins.flatMap(\.translations)
    }

    /// Три неверных варианта перевода для режима выбора.
    ///
    /// Берутся из той же колоды; если слов не хватает — из остальных активных колод.
    /// При совсем маленькой колоде вариантов будет меньше четырёх, но не меньше двух.
    /// Перевод слова с тем же текстом намеренно не исключается: он тоже засчитывается
    /// (см. `acceptedTranslations(for:)`), и тогда верных вариантов на экране два.
    ///
    /// Если у слова указана часть речи, сначала берутся слова той же части речи:
    /// иначе вариант отсеивается по форме («бежать» среди «стол», «окно», «книга»).
    /// У форм глагола среди них в первую очередь — формы с той же пометкой лица.
    /// Своей части речи не хватило — варианты добираются из любых слов.
    static func distractors(
        for word: Word,
        in context: ModelContext,
        count: Int = 3
    ) -> [String] {
        let correct = Set(word.translations.map(AnswerChecker.normalize))
        let kind = word.partOfSpeech
        let person = personTag(of: word.translations.first)

        func pick(from words: [Word]) -> [Word] {
            words.filter { candidate in
                guard candidate.id != word.id, let first = candidate.translations.first else { return false }
                return !correct.contains(AnswerChecker.normalize(first))
            }
        }

        /// 0 — та же часть речи и то же лицо, 1 — та же часть речи, 2 — остальные.
        func rank(_ candidate: Word) -> Int {
            guard let kind else { return 0 }
            guard candidate.partOfSpeech == kind else { return 2 }
            return personTag(of: candidate.translations.first) == person ? 0 : 1
        }

        var pool = pick(from: word.deck?.sortedWords ?? [])
        if pool.count(where: { rank($0) < 2 }) < count {
            let others = activeDecks(in: context)
                .filter { $0.id != word.deck?.id }
                .flatMap(\.sortedWords)
            pool += pick(from: others)
        }

        // Перемешивание, затем устойчивая сортировка по рангу: внутри ранга порядок
        // остаётся случайным, а своя колода не теряет приоритет при равном ранге.
        let ownDeck = word.deck?.id
        let ranked = pool.shuffled().enumerated().sorted { left, right in
            let leftKey = (rank(left.element), left.element.deck?.id == ownDeck ? 0 : 1)
            let rightKey = (rank(right.element), right.element.deck?.id == ownDeck ? 0 : 1)
            return leftKey != rightKey ? leftKey < rightKey : left.offset < right.offset
        }

        // Удаление повторов с сохранением порядка.
        var seen = Set<String>()
        return ranked
            .compactMap { $0.element.translations.first }
            .filter { seen.insert(AnswerChecker.normalize($0)).inserted }
            .prefix(count)
            .map { $0 }
    }

    /// Пометка лица в скобках в конце перевода: «хотеть (du)» → `du`.
    /// У инфинитива и у слов без пометки — `nil`, поэтому инфинитивы тянутся к инфинитивам.
    static func personTag(of translation: String?) -> String? {
        guard let translation,
              translation.hasSuffix(")"),
              let open = translation.lastIndex(of: "(") else { return nil }
        let inner = translation[translation.index(after: open)..<translation.index(before: translation.endIndex)]
        let tag = inner.trimmingCharacters(in: .whitespaces).lowercased()
        return tag.isEmpty ? nil : tag
    }
}
