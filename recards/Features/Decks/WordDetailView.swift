import SwiftUI
import SwiftData

/// Карточка слова: содержимое, состояние обеих карточек повторения и управление прогрессом.
struct WordDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var word: Word

    @State private var isEditing = false
    @State private var isConfirmingReset = false

    var body: some View {
        List {
            Section("Слово") {
                LabeledContent("Слово", value: word.text)
                LabeledContent("Переводы", value: word.translations.joined(separator: ", "))
                if let transcription = word.transcription {
                    LabeledContent("Транскрипция", value: transcription)
                }
            }

            if let example = word.example {
                Section("Пример") {
                    Text(example)
                    if let translation = word.exampleTranslation {
                        Text(translation).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Прогресс") {
                ForEach(CardDirection.allCases, id: \.self) { direction in
                    if let card = word.card(for: direction) {
                        CardProgressRow(card: card, direction: direction)
                    }
                }
            }

            Section {
                if word.isLearned {
                    Button("Вернуть в ротацию", systemImage: "arrow.uturn.backward") {
                        returnToRotation()
                    }
                }
                Button("Сбросить прогресс", systemImage: "arrow.counterclockwise", role: .destructive) {
                    isConfirmingReset = true
                }
                .disabled(word.isNew)
            } footer: {
                if word.isNew {
                    Text("Слово ещё не изучалось.")
                }
            }
        }
        .navigationTitle(word.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Изменить") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { WordFormView(word: word) }
        }
        .confirmationDialog(
            "Сбросить прогресс по слову?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) { resetProgress() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Слово снова станет новым, история повторений будет обнулена.")
        }
    }

    private func resetProgress() {
        word.startedAt = nil
        for card in word.cards ?? [] {
            card.resetProgress()
        }
    }

    private func returnToRotation() {
        for card in word.cards ?? [] where card.isArchived {
            card.resetProgress()
        }
    }
}

// MARK: - Состояние одной карточки

private struct CardProgressRow: View {
    let card: ReCard
    let direction: CardDirection

    private var title: LocalizedStringKey {
        switch direction {
        case .production: return "Перевод → слово"
        case .recognition: return "Слово → перевод"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            if !card.isArchived, card.state != .new {
                Text(dueDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: LocalizedStringKey {
        if card.isArchived { return "выучено" }
        switch card.state {
        case .new: return "новое"
        case .learning: return "заучивается"
        case .review: return "повторение"
        case .relearning: return "переучивается"
        }
    }

    private var statusColor: Color {
        if card.isArchived { return .green }
        return card.state == .new ? .blue : .orange
    }

    /// Устойчивость показывается словами: «помнится примерно две недели» понятнее числа.
    private var dueDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let next = formatter.localizedString(for: card.due, relativeTo: Date())
        let retention = Int(card.stability.rounded())
        return "Следующий показ \(next) · держится в памяти ≈ \(retention) дн."
    }
}

#Preview {
    NavigationStack {
        WordDetailView(word: PreviewData.sampleWord)
    }
    .modelContainer(PreviewData.container)
}
