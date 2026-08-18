import SwiftUI
import SwiftData

/// Список колод.
struct DecksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    @State private var isCreating = false
    @State private var deckPendingDeletion: Deck?

    var body: some View {
        List {
            ForEach(decks) { deck in
                NavigationLink(value: deck) {
                    DeckRow(deck: deck)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deckPendingDeletion = deck
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Колоды")
        .navigationDestination(for: Deck.self) { deck in
            DeckDetailView(deck: deck)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Новая колода", systemImage: "plus") {
                    isCreating = true
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                DeckFormView()
            }
        }
        .overlay {
            if decks.isEmpty {
                EmptyDecksView { isCreating = true }
            }
        }
        .alert(
            "Удалить колоду «\(deckPendingDeletion?.name ?? "")»?",
            isPresented: Binding(
                get: { deckPendingDeletion != nil },
                set: { if !$0 { deckPendingDeletion = nil } }
            ),
            presenting: deckPendingDeletion
        ) { deck in
            Button("Удалить", role: .destructive) { delete(deck) }
            Button("Отмена", role: .cancel) {}
        } message: { deck in
            Text(deletionWarning(for: deck))
        }
    }

    /// Предупреждение называет точное число слов, прогресс по которым будет потерян.
    private func deletionWarning(for deck: Deck) -> String {
        let started = (deck.words ?? []).count { !$0.isNew }
        guard started > 0 else {
            return "Колода содержит \((deck.words ?? []).count) слов. Действие необратимо."
        }
        return "Будет потерян прогресс по \(started) словам. Действие необратимо."
    }

    private func delete(_ deck: Deck) {
        context.delete(deck)
        deckPendingDeletion = nil
    }
}

// MARK: - Строка списка

private struct DeckRow: View {
    @Bindable var deck: Deck

    var body: some View {
        HStack(spacing: 12) {
            Text(deck.emoji)
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.headline)
                Text(deck.languagePairDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CountersView(deck: deck)
            }

            Spacer()

            // Переключатель определяет, попадают ли слова колоды в общие сессии.
            Toggle("Учить", isOn: $deck.isActive)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

private struct CountersView: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 10) {
            counter(deck.newWordsCount, label: "новых", color: .blue)
            counter(deck.learningWordsCount, label: "учится", color: .orange)
            counter(deck.learnedWordsCount, label: "выучено", color: .green)
        }
        .font(.caption2)
    }

    private func counter(_ value: Int, label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value) ") + Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Пустое состояние

private struct EmptyDecksView: View {
    let onCreate: () -> Void
    @State private var isShowingFormat = false

    var body: some View {
        ContentUnavailableView {
            Label("Пока нет колод", systemImage: "rectangle.stack")
        } description: {
            Text("Создайте колоду и добавьте слова вручную или загрузите готовый файл.")
        } actions: {
            Button("Создать колоду", action: onCreate)
                .buttonStyle(.borderedProminent)
            Button("Показать формат файла") { isShowingFormat = true }
        }
        .sheet(isPresented: $isShowingFormat) {
            NavigationStack { FormatHelpView() }
        }
    }
}

#Preview {
    NavigationStack {
        DecksView()
    }
    .modelContainer(PreviewData.container)
}
