import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Загрузка слов в колоду из файла или из буфера обмена.
///
/// Импорт всегда проходит через предпросмотр: пользователь видит, сколько записей
/// найдено и что именно было пропущено, прежде чем что-то попадёт в базу.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck

    @State private var pastedText = ""
    @State private var isChoosingFile = false
    @State private var isShowingFormat = false
    @State private var result: ImportResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button("Выбрать файл", systemImage: "folder") {
                    isChoosingFile = true
                }
            } footer: {
                Text("Поддерживаются CSV, TSV и JSON.")
            }

            Section {
                TextEditor(text: $pastedText)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Или вставьте текст")
            } footer: {
                Text("Каждая строка: слово, затем перевод. Несколько переводов разделяются знаком «;».")
            }

            Section {
                Button("Показать формат файла", systemImage: "questionmark.circle") {
                    isShowingFormat = true
                }
            }
        }
        .navigationTitle("Импорт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Далее") { parse(pastedText) }
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.json, .commaSeparatedText, .tabSeparatedText, .plainText, .text]
        ) { outcome in
            handleFileSelection(outcome)
        }
        .sheet(isPresented: $isShowingFormat) {
            NavigationStack { FormatHelpView() }
        }
        .navigationDestination(item: $result) { parsed in
            ImportPreviewView(deck: deck, result: parsed) {
                dismiss()
            }
        }
        .alert("Не удалось прочитать файл", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func parse(_ text: String) {
        result = ImportService.parse(text, existing: deck.existingWordKeys)
    }

    private func handleFileSelection(_ outcome: Result<URL, Error>) {
        switch outcome {
        case .failure(let error):
            errorMessage = error.localizedDescription

        case .success(let url):
            // Файл лежит вне песочницы приложения, доступ нужно запрашивать явно.
            let needsRelease = url.startAccessingSecurityScopedResource()
            defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    errorMessage = "Файл должен быть в кодировке UTF-8."
                    return
                }
                parse(text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Предпросмотр

/// Сводка разбора: что будет добавлено и что пропущено.
struct ImportPreviewView: View {
    @Environment(\.modelContext) private var context
    let deck: Deck
    let result: ImportResult
    let onFinish: () -> Void

    var body: some View {
        List {
            Section {
                LabeledContent("Будет добавлено", value: "\(result.words.count)")
                if !result.skipped.isEmpty {
                    LabeledContent("Пропущено", value: "\(result.skipped.count)")
                }
            } footer: {
                if result.words.isEmpty {
                    Text("Не найдено ни одной подходящей записи.")
                }
            }

            if !result.words.isEmpty {
                Section("Новые слова") {
                    ForEach(Array(result.words.enumerated()), id: \.offset) { _, word in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.word)
                            Text(word.translations.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !result.skipped.isEmpty {
                Section("Пропущенные строки") {
                    ForEach(result.skipped) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Строка \(row.line): \(row.reason.localizedDescription)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            if !row.content.isEmpty {
                                Text(row.content)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Предпросмотр")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Импортировать", action: performImport)
                    .disabled(result.words.isEmpty)
            }
        }
    }

    private func performImport() {
        for payload in result.words {
            let word = Word(
                text: payload.word,
                translations: payload.translations,
                transcription: payload.transcription,
                example: payload.example,
                exampleTranslation: payload.exampleTranslation,
                partOfSpeech: PartOfSpeech(code: payload.partOfSpeech)
            )
            word.deck = deck
            context.insert(word)
            deck.words = (deck.words ?? []) + [word]
            word.ensureCard()
        }
        onFinish()
    }
}
