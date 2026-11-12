import SwiftUI

/// Справка по формату файлов импорта.
///
/// Показывается по кнопке рядом с импортом: пользователь должен видеть точный образец,
/// а не догадываться о структуре.
struct FormatHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private static let csvSample = """
    word,translation,transcription,example,exampleTranslation,partOfSpeech
    der Hund,собака;пёс,/hʊnt/,Der Hund bellt.,Собака лает.,noun
    die Katze,кошка,/ˈkatsə/,,,noun
    liest,читать (du),,,,verb
    """

    private static let jsonSample = """
    {
      "name": "Немецкий A1",
      "sourceLanguage": "de-DE",
      "targetLanguage": "ru-RU",
      "words": [
        {
          "word": "der Hund",
          "translations": ["собака", "пёс"],
          "transcription": "/hʊnt/",
          "example": "Der Hund bellt.",
          "exampleTranslation": "Собака лает.",
          "partOfSpeech": "noun"
        }
      ]
    }
    """

    /// Промпт для любого ИИ-чата: пользователь вставляет его, подставляет свои значения
    /// и импортирует полученный CSV. Генерации внутри приложения нет (SPEC, раздел 16) —
    /// это только текст, описывающий формат и договорённости о данных.
    private static var aiPrompt: String {
        String(localized: """
        Составь колоду карточек для приложения Recards.

        Изучаемый язык: [например, немецкий]. Язык перевода: [например, русский]. Тема и уровень: [например, еда, A1]. Количество слов: [например, 50].

        Формат — CSV в UTF-8, первая строка — заголовок:
        word,translation,transcription,example,exampleTranslation,partOfSpeech

        Правила:
        - word — слово на изучаемом языке. Существительные пиши с артиклем, если он есть в языке: der Hund.
        - translation — перевод. Несколько переводов (синонимы) — в одном поле через точку с запятой: собака;пёс. Не разноси синонимы по разным строкам.
        - transcription — IPA в косых чертах: /hʊnt/. Для форм глагола оставляй пустым.
        - example и exampleTranslation — короткий пример со словом и его перевод. Для форм глагола оставляй пустыми.
        - partOfSpeech — часть речи, одно из значений: noun (существительное), verb (глагол), adjective (прилагательное), other (всё остальное). У форм глагола тоже verb.
        - Значения с запятой внутри заключай в двойные кавычки.
        - Глаголы: сначала инфинитив отдельной строкой с обычным переводом (lesen,читать). Затем каждая форма настоящего времени — своей строкой, без местоимения, а лица указаны в скобках в переводе: lese,читать (ich).
        - Для немецкого группы лиц такие: ich; du; er/sie/es; ihr; wir/sie/Sie. Строка wir/sie/Sie нужна, даже если её форма совпадает с инфинитивом.
        - Для других языков группируй лица по их грамматике: лица с одинаковой формой — в одной строке через косую черту, а если формы для «он» и «она» различаются, это разные строки.
        - Одинаковое слово с разными переводами — это нормально (will для ich и для er/sie/es). Не повторяй только строки, где совпадают и слово, и перевод.

        Выведи только CSV, без пояснений.
        """)
    }

    var body: some View {
        List {
            Section {
                Text("Обязательны только первые две колонки: слово и перевод. Остальные можно опустить.")
                Text("Несколько переводов разделяются знаком «;» — при проверке засчитывается любой из них.")
                Text("Артикль пишется вместе со словом: «der Hund».")
                Text("Глагол: инфинитив отдельной строкой, затем каждая форма — своей строкой, а лицо указывается в скобках в переводе: «liest,читать (du)».")
                Text("Часть речи — необязательная шестая колонка: noun, verb, adjective или other. По ней подбираются варианты в упражнении с выбором перевода.")
            } header: {
                Text("Правила")
            }

            Section {
                CodeBlock(text: Self.csvSample)
                Button("Скопировать образец", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = Self.csvSample
                }
            } header: {
                Text("CSV или TSV")
            } footer: {
                Text("Кодировка UTF-8. Первая строка с заголовком необязательна. Разделитель — запятая или табуляция, определяется автоматически. Значения с запятой внутри заключаются в кавычки.")
            }

            Section {
                CodeBlock(text: Self.jsonSample)
                Button("Скопировать образец", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = Self.jsonSample
                }
            } header: {
                Text("JSON")
            } footer: {
                Text("Тот же формат используется при экспорте, поэтому выгруженный файл загружается обратно без потерь.")
            }

            Section {
                Text("Строки без слова или без перевода пропускаются.")
                Text("Повтором считается строка с тем же словом и теми же переводами — она пропускается. То же слово с другим переводом (например, форма глагола) становится отдельной карточкой, поэтому синонимы пишутся в одной строке через «;».")
                Text("Перед импортом показывается сводка: сколько записей найдено и что пропущено.")
            } header: {
                Text("Что будет пропущено")
            }

            Section {
                Text(verbatim: Self.aiPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Скопировать промпт", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = Self.aiPrompt
                }
            } header: {
                Text("Колода с помощью ИИ")
            } footer: {
                Text("Вставьте промпт в любой ИИ-чат, замените значения в квадратных скобках и импортируйте полученный CSV. Результат стоит просмотреть: модель может ошибиться в формах и переводах.")
            }
        }
        .navigationTitle("Формат файла")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }
}

private struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    NavigationStack {
        FormatHelpView()
    }
}
