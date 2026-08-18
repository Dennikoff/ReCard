import SwiftUI
import SwiftData

/// Создание новой колоды либо переименование существующей.
///
/// Языковая пара задаётся только при создании: менять её у колоды с прогрессом
/// нельзя, потому что это обесценило бы накопленные карточки.
struct DeckFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Редактируемая колода. `nil` означает создание новой.
    var deck: Deck?

    @State private var name: String = ""
    @State private var emoji: String = "📘"
    @State private var sourceLanguage: String = ""
    @State private var targetLanguage: String = ""
    @State private var languages: [LanguageOption] = []

    private var isEditing: Bool { deck != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !sourceLanguage.isEmpty
            && !targetLanguage.isEmpty
            && sourceLanguage != targetLanguage
    }

    var body: some View {
        Form {
            Section {
                TextField("Название", text: $name)
                EmojiField(emoji: $emoji)
            }

            Section {
                if isEditing {
                    LabeledContent("Язык слова", value: displayName(sourceLanguage))
                    LabeledContent("Язык перевода", value: displayName(targetLanguage))
                } else {
                    languagePicker("Язык слова", selection: $sourceLanguage)
                    languagePicker("Язык перевода", selection: $targetLanguage)
                }
            } header: {
                Text("Языки")
            } footer: {
                if isEditing {
                    Text("Языки колоды нельзя изменить после создания. Создайте новую колоду, если нужна другая пара.")
                } else if sourceLanguage == targetLanguage, !sourceLanguage.isEmpty {
                    Text("Языки слова и перевода должны различаться.")
                        .foregroundStyle(.red)
                } else {
                    Text("В списке только языки, для которых в системе есть голос: их приложение сможет произнести.")
                }
            }
        }
        .navigationTitle(isEditing ? "Колода" : "Новая колода")
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
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(languages) { language in
                Text(language.displayName).tag(language.code)
            }
        }
    }

    private func displayName(_ code: String) -> String {
        LanguageCatalog.displayName(for: code)
    }

    private func loadInitialState() {
        languages = LanguageCatalog.available()

        if let deck {
            name = deck.name
            emoji = deck.emoji
            sourceLanguage = deck.sourceLanguage
            targetLanguage = deck.targetLanguage
            return
        }

        guard sourceLanguage.isEmpty else { return }
        let target = LanguageCatalog.defaultTargetLanguage()
        targetLanguage = target
        // Язык слова по умолчанию — любой отличный от языка интерфейса.
        sourceLanguage = languages.first { $0.code != target }?.code ?? target
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)

        if let deck {
            deck.name = trimmedName
            deck.emoji = trimmedEmoji.isEmpty ? "📘" : trimmedEmoji
        } else {
            let deck = Deck(
                name: trimmedName,
                emoji: trimmedEmoji.isEmpty ? "📘" : trimmedEmoji,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            context.insert(deck)
        }

        dismiss()
    }
}

// MARK: - Поле эмодзи

private struct EmojiField: View {
    @Binding var emoji: String

    private let suggestions = ["📘", "🇩🇪", "🇬🇧", "🍽️", "✈️", "💼", "🏠", "🎓", "❤️", "🔤"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Значок") {
                TextField("📘", text: $emoji)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: emoji) { _, newValue in
                        // Значок — ровно один символ.
                        if let first = newValue.first {
                            emoji = String(first)
                        }
                    }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            emoji = suggestion
                        } label: {
                            Text(suggestion)
                                .font(.title2)
                                .padding(6)
                                .background(
                                    emoji == suggestion ? Color.accentColor.opacity(0.2) : .clear,
                                    in: .rect(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    NavigationStack {
        DeckFormView()
    }
    .modelContainer(PreviewData.container)
}
