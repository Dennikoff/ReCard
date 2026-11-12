import SwiftUI

/// Карточка «перевод → слово»: ответ вводится с клавиатуры.
struct ProductionCardView: View {
    let model: SessionViewModel

    @FocusState private var isFieldFocused: Bool
    @State private var autoAdvanceTask: Task<Void, Never>?
    /// Автопереход отменён тапом после верного ответа: пользователь хочет
    /// рассмотреть или послушать слово. Дальше — только по кнопке.
    @State private var isHeld = false

    private var word: Word? { model.currentWord }

    private var verdict: AnswerVerdict? {
        if case .answered(let value) = model.stage { return value }
        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            card

            if let verdict {
                feedback(verdict)
            } else {
                inputArea
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .animation(.snappy, value: model.stage)
        .onAppear { isFieldFocused = true }
        .onChange(of: model.stage) { _, newValue in
            handleStageChange(newValue)
        }
        .onDisappear { autoAdvanceTask?.cancel() }
        // Тап в любом месте после верного ответа останавливает автопереход.
        .contentShape(.rect)
        .onTapGesture { hold() }
    }

    // MARK: - Карточка

    private var card: some View {
        VStack(spacing: 14) {
            Text(word?.translations.joined(separator: ", ") ?? "")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)

            if verdict != nil {
                revealedContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(borderColor, lineWidth: verdict == nil ? 0 : 2)
        }
    }

    /// Содержимое, раскрываемое после ответа: само слово, транскрипция, звук и пример.
    private var revealedContent: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(spacing: 10) {
                Text(word?.text ?? "")
                    .font(.title2.bold())

                Button {
                    speak()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Произнести слово")
            }

            if let transcription = word?.transcription {
                Text(transcription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let example = word?.example {
                VStack(spacing: 3) {
                    Text(example).font(.callout)
                    if let translation = word?.exampleTranslation {
                        Text(translation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var borderColor: Color {
        switch verdict {
        case .correct, .correctWithTypo: return .green
        case .incorrect: return .red
        case nil: return .clear
        }
    }

    // MARK: - Ввод

    private var inputArea: some View {
        VStack(spacing: 12) {
            TextField("Ответ", text: Binding(
                get: { model.typedAnswer },
                set: { model.typedAnswer = $0 }
            ))
            // Без этих модификаторов система сама исправит и капитализирует ввод,
            // молча ломая проверку ответа.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.plain)
            .font(.title3)
            .multilineTextAlignment(.center)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .focused($isFieldFocused)
            .submitLabel(.done)
            .onSubmit(check)

            Button(action: check) {
                Text("Проверить")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Разбор ответа

    @ViewBuilder
    private func feedback(_ verdict: AnswerVerdict) -> some View {
        VStack(spacing: 12) {
            switch verdict {
            case .correct:
                Label("Верно", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)

            case .correctWithTypo:
                VStack(spacing: 4) {
                    Label("Почти верно", systemImage: "checkmark.circle")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    Text("Правильное написание: \(word?.text ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .incorrect:
                VStack(spacing: 8) {
                    Label("Неверно", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.headline)

                    Text(model.lastInput)
                        .strikethrough()
                        .foregroundStyle(.secondary)

                    Button("Засчитать как верный", systemImage: "hand.thumbsup") {
                        model.markLastAnswerCorrect()
                    }
                    .font(.footnote)
                }
            }

            // Верный ответ уходит сам, неверный требует осознанного тапа —
            // чтобы правильное написание успели прочитать. Если верный ответ
            // остановлен тапом, тоже нужна кнопка.
            if verdict == .incorrect || isHeld {
                Button(action: advance) {
                    Text("Дальше")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Действия

    private func check() {
        guard !model.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isFieldFocused = false
        model.submitTypedAnswer()
    }

    private func advance() {
        autoAdvanceTask?.cancel()
        model.advanceAfterFeedback()
        isFieldFocused = true
    }

    private func speak() {
        model.speakCurrentWord()
        hold()
    }

    /// Останавливает автопереход после верного ответа.
    private func hold() {
        guard let verdict, verdict != .incorrect else { return }
        autoAdvanceTask?.cancel()
        isHeld = true
    }

    private func handleStageChange(_ stage: SessionStage) {
        autoAdvanceTask?.cancel()
        isHeld = false

        guard case .answered(let value) = stage, value != .incorrect else {
            if case .asking = stage { isFieldFocused = true }
            return
        }

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            advance()
        }
    }
}
