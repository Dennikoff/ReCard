import SwiftUI
import SwiftData

/// Добавление нового слова или правка существующего.
///
/// Правка текста не сбрасывает прогресс: исправление опечатки не должно стоить
/// пользователю месяца работы.
struct WordFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Колода, в которую добавляется слово. Требуется только при создании.
    var deck: Deck?
    /// Редактируемое слово. `nil` означает создание нового.
    var word: Word?

    @State private var text = ""
    @State private var translationsText = ""
    @State private var transcription = ""
    @State private var example = ""
    @State private var exampleTranslation = ""
    @State private var duplicateWarning: String?

    private var isEditing: Bool { word != nil }

    private var translations: [String] {
        translationsText
            .split(separator: ImportService.translationSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !translations.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Слово", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Переводы через ;", text: $translationsText, axis: .vertical)
            } header: {
                Text("Обязательно")
            } footer: {
                if let duplicateWarning {
                    Text(duplicateWarning).foregroundStyle(.orange)
                } else if translations.count > 1 {
                    Text("Засчитывается любой из переводов: \(translations.joined(separator: ", ")).")
                } else {
                    Text("Артикль пишется вместе со словом: «der Hund». Тогда его нужно будет ввести при проверке.")
                }
            }

            Section("Необязательно") {
                TextField("Транскрипция", text: $transcription)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Пример", text: $example, axis: .vertical)
                TextField("Перевод примера", text: $exampleTranslation, axis: .vertical)
            }
        }
        .navigationTitle(isEditing ? "Слово" : "Новое слово")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово", action: save).disabled(!canSave)
            }
        }
        .task { loadInitialState() }
        .onChange(of: text) { _, _ in checkDuplicate() }
    }

    private func loadInitialState() {
        guard let word, text.isEmpty else { return }
        text = word.text
        translationsText = word.translations.joined(separator: "; ")
        transcription = word.transcription ?? ""
        example = word.example ?? ""
        exampleTranslation = word.exampleTranslation ?? ""
    }

    /// Предупреждение о дубликате не блокирует сохранение — решает пользователь.
    private func checkDuplicate() {
        let container = deck ?? word?.deck
        guard let container else { duplicateWarning = nil; return }

        let key = AnswerChecker.normalize(text)
        guard !key.isEmpty else { duplicateWarning = nil; return }

        let clash = (container.words ?? []).contains {
            $0.id != word?.id && AnswerChecker.normalize($0.text) == key
        }
        duplicateWarning = clash ? "Такое слово уже есть в колоде." : nil
    }

    private func save() {
        func cleaned(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let word {
            word.text = trimmedText
            word.translations = translations
            word.transcription = cleaned(transcription)
            word.example = cleaned(example)
            word.exampleTranslation = cleaned(exampleTranslation)
        } else if let deck {
            let word = Word(
                text: trimmedText,
                translations: translations,
                transcription: cleaned(transcription),
                example: cleaned(example),
                exampleTranslation: cleaned(exampleTranslation)
            )
            word.deck = deck
            context.insert(word)
            deck.words = (deck.words ?? []) + [word]
            word.ensureCards()
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        WordFormView(deck: PreviewData.sampleDeck)
    }
    .modelContainer(PreviewData.container)
}
