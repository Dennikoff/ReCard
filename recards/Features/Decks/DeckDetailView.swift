import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Фильтр списка слов внутри колоды.
private enum WordFilter: String, CaseIterable, Identifiable {
    case all, new, learning, learned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .new: return "Новые"
        case .learning: return "Учатся"
        case .learned: return "Выучено"
        }
    }

    func matches(_ word: Word) -> Bool {
        switch self {
        case .all: return true
        case .new: return word.isNew
        case .learning: return !word.isNew && !word.isLearned
        case .learned: return word.isLearned
        }
    }
}

/// Содержимое одной колоды.
struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck

    @State private var filter: WordFilter = .all
    @State private var searchText = ""
    @State private var isAddingWord = false
    @State private var isEditingDeck = false
    @State private var isImporting = false
    @State private var isShowingFormat = false
    @State private var exportDocument: TextFileDocument?
    @State private var exportKind: ExportKind = .json
    @State private var wordPendingDeletion: Word?

    private enum ExportKind {
        case json, csv

        var contentType: UTType { self == .json ? .json : .commaSeparatedText }
        var fileExtension: String { self == .json ? "json" : "csv" }
    }

    private var filteredWords: [Word] {
        let base = deck.sortedWords.filter(filter.matches)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }

        let normalizedQuery = AnswerChecker.normalize(query)
        return base.filter { word in
            AnswerChecker.normalize(word.text).contains(normalizedQuery)
                || word.translations.contains {
                    AnswerChecker.normalize($0).contains(normalizedQuery)
                }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Фильтр", selection: $filter) {
                    ForEach(WordFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                ForEach(filteredWords) { word in
                    NavigationLink(value: word) {
                        WordRow(word: word)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            wordPendingDeletion = word
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            } header: {
                if !filteredWords.isEmpty {
                    Text("\(filteredWords.count) слов")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Поиск по словам и переводам")
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Word.self) { word in
            WordDetailView(word: word)
        }
        .toolbar { toolbarContent }
        .overlay {
            if deck.sortedWords.isEmpty {
                emptyDeckView
            } else if filteredWords.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .sheet(isPresented: $isAddingWord) {
            NavigationStack { WordFormView(deck: deck) }
        }
        .sheet(isPresented: $isEditingDeck) {
            NavigationStack { DeckFormView(deck: deck) }
        }
        .sheet(isPresented: $isImporting) {
            NavigationStack { ImportView(deck: deck) }
        }
        .sheet(isPresented: $isShowingFormat) {
            NavigationStack { FormatHelpView() }
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: exportKind.contentType,
            defaultFilename: ExportService.fileName(for: deck.name, extension: exportKind.fileExtension)
        ) { _ in
            exportDocument = nil
        }
        .alert(
            "Удалить слово?",
            isPresented: Binding(
                get: { wordPendingDeletion != nil },
                set: { if !$0 { wordPendingDeletion = nil } }
            ),
            presenting: wordPendingDeletion
        ) { word in
            Button("Удалить", role: .destructive) {
                context.delete(word)
                wordPendingDeletion = nil
            }
            Button("Отмена", role: .cancel) {}
        } message: { word in
            Text("«\(word.text)» будет удалено вместе с прогрессом.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Ещё", systemImage: "ellipsis") {
                Button("Добавить слово", systemImage: "plus") { isAddingWord = true }
                Button("Импортировать", systemImage: "square.and.arrow.down") { isImporting = true }

                Menu("Экспортировать", systemImage: "square.and.arrow.up") {
                    Button("Файл JSON") { export(.json) }
                    Button("Файл CSV") { export(.csv) }
                }
                .disabled(deck.sortedWords.isEmpty)

                Divider()

                Button("Переименовать", systemImage: "pencil") { isEditingDeck = true }
                Button("Формат файла", systemImage: "questionmark.circle") { isShowingFormat = true }
            }
        }
    }

    private var emptyDeckView: some View {
        ContentUnavailableView {
            Label("Колода пуста", systemImage: "tray")
        } description: {
            Text("Добавьте слова вручную или загрузите файл со списком.")
        } actions: {
            Button("Добавить слово") { isAddingWord = true }
                .buttonStyle(.borderedProminent)
            Button("Импортировать") { isImporting = true }
            Button("Показать формат файла") { isShowingFormat = true }
        }
    }

    private func export(_ kind: ExportKind) {
        let payload = deck.payload
        exportKind = kind

        switch kind {
        case .json:
            guard let data = try? ExportService.makeJSON(payload) else { return }
            exportDocument = TextFileDocument(text: String(decoding: data, as: UTF8.self))
        case .csv:
            exportDocument = TextFileDocument(text: ExportService.makeCSV(payload))
        }
    }
}

// MARK: - Строка слова

private struct WordRow: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(word.text)
                    .font(.body)
                statusBadge
            }
            Text(word.translations.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if word.isLearned {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        } else if word.isNew {
            Image(systemName: "circle.dashed")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: PreviewData.sampleDeck)
    }
    .modelContainer(PreviewData.container)
}
