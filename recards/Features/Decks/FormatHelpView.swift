import SwiftUI

/// Справка по формату файлов импорта.
///
/// Показывается по кнопке рядом с импортом: пользователь должен видеть точный образец,
/// а не догадываться о структуре.
struct FormatHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private static let csvSample = """
    word,translation,transcription,example,exampleTranslation
    der Hund,собака;пёс,/hʊnt/,Der Hund bellt.,Собака лает.
    die Katze,кошка,/ˈkatsə/,,
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
          "exampleTranslation": "Собака лает."
        }
      ]
    }
    """

    var body: some View {
        List {
            Section {
                Text("Обязательны только первые две колонки: слово и перевод. Остальные можно опустить.")
                Text("Несколько переводов разделяются знаком «;» — при проверке засчитывается любой из них.")
                Text("Артикль пишется вместе со словом: «der Hund».")
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
                Text("Слова, которые уже есть в колоде, пропускаются как повторы.")
                Text("Перед импортом показывается сводка: сколько записей найдено и что пропущено.")
            } header: {
                Text("Что будет пропущено")
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
