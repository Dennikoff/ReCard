import Foundation

/// Сравнение введённого пользователем ответа с ожидаемыми вариантами.
///
/// Правила зафиксированы в спецификации и намеренно снисходительны: несправедливо
/// засчитанная ошибка обходится дороже, чем изредка прощённая описка.
nonisolated enum AnswerChecker {

    /// Минимальная длина ожидаемого ответа, при которой прощается одна опечатка.
    /// На коротких словах отличие в один символ — это уже другое слово.
    static let minimumLengthForTypoTolerance = 4

    // MARK: - Нормализация

    /// Замены диакритики и лигатур, применяемые к обеим сравниваемым строкам.
    ///
    /// Благодаря симметрии пользователь может ввести и `Fuß`, и `fuss` — оба варианта
    /// приводятся к одной форме.
    private static let substitutions: [(String, String)] = [
        ("ä", "ae"),
        ("ö", "oe"),
        ("ü", "ue"),
        ("ß", "ss"),
        ("ё", "е"),
    ]

    /// Приводит строку к форме, в которой выполняется сравнение.
    ///
    /// Регистр не проверяется: требовать заглавную букву на каждом немецком
    /// существительном на телефонной клавиатуре слишком дорого.
    static func normalize(_ string: String) -> String {
        var result = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Схлопывание внутренних пробелов и переносов в один пробел.
        result = result
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        for (from, to) in substitutions {
            result = result.replacingOccurrences(of: from, with: to)
        }

        return result
    }

    // MARK: - Сравнение

    /// Сравнивает ввод со всеми допустимыми вариантами и возвращает лучший исход.
    static func check(input: String, against expected: [String]) -> AnswerVerdict {
        let normalizedInput = normalize(input)
        guard !normalizedInput.isEmpty else { return .incorrect }

        let normalizedExpected = expected
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !normalizedExpected.isEmpty else { return .incorrect }

        if normalizedExpected.contains(normalizedInput) {
            return .correct
        }

        let inputCharacters = Array(normalizedInput)
        for variant in normalizedExpected {
            let variantCharacters = Array(variant)
            guard variantCharacters.count >= minimumLengthForTypoTolerance else { continue }
            // Отличие больше чем на один символ отсекается без подсчёта расстояния.
            guard abs(variantCharacters.count - inputCharacters.count) <= 1 else { continue }

            if distance(inputCharacters, variantCharacters) == 1 {
                return .correctWithTypo
            }
        }

        return .incorrect
    }

    /// Возвращает вариант ответа, ближайший к введённому. Используется в разборе ошибки.
    static func closestMatch(for input: String, among expected: [String]) -> String? {
        let normalizedInput = Array(normalize(input))
        return expected.min { left, right in
            distance(normalizedInput, Array(normalize(left)))
                < distance(normalizedInput, Array(normalize(right)))
        }
    }

    // MARK: - Расстояние между строками

    /// Расстояние Дамерау — Левенштейна в варианте оптимального выравнивания строк.
    ///
    /// Отличается от обычного расстояния Левенштейна тем, что перестановка двух соседних
    /// символов стоит одну операцию, а не две. Это принципиально для проверки ответа:
    /// перестановка соседних букв — самая частая описка при быстром наборе, и засчитывать
    /// её как незнание слова было бы несправедливо.
    static func distance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        // Полная матрица, а не две строки: учёт перестановки требует доступа
        // к позиции на два шага назад по обеим осям.
        var matrix = [[Int]](
            repeating: [Int](repeating: 0, count: rhs.count + 1),
            count: lhs.count + 1
        )
        for i in 0...lhs.count { matrix[i][0] = i }
        for j in 0...rhs.count { matrix[0][j] = j }

        for i in 1...lhs.count {
            for j in 1...rhs.count {
                let substitutionCost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                var best = min(
                    matrix[i - 1][j] + 1,      // удаление
                    matrix[i][j - 1] + 1,      // вставка
                    matrix[i - 1][j - 1] + substitutionCost
                )

                // Перестановка двух соседних символов.
                if i > 1, j > 1, lhs[i - 1] == rhs[j - 2], lhs[i - 2] == rhs[j - 1] {
                    best = min(best, matrix[i - 2][j - 2] + 1)
                }

                matrix[i][j] = best
            }
        }

        return matrix[lhs.count][rhs.count]
    }
}
