import SwiftUI

/// Карточка «слово → перевод»: ответ выбирается из вариантов.
///
/// Печатать перевод здесь было бы дорого по времени и постоянно спотыкалось бы
/// о синонимы, поэтому используется выбор.
struct RecognitionCardView: View {
    let model: SessionViewModel

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

            optionsList

            // После ошибки или остановки тапом автоперехода нет — только по кнопке.
            if verdict == .incorrect || isHeld {
                Button(action: advance) {
                    Text("Дальше")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .animation(.snappy, value: model.stage)
        .onChange(of: model.stage) { _, newValue in handleStageChange(newValue) }
        .onDisappear { autoAdvanceTask?.cancel() }
        // Тап в любом месте после верного ответа останавливает автопереход.
        .contentShape(.rect)
        .onTapGesture { hold() }
    }

    private var card: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(word?.text ?? "")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)

                // Здесь звук ответа не выдаёт: слово уже на экране.
                Button {
                    speak()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Произнести слово")
            }

            if let transcription = word?.transcription, verdict != nil {
                Text(transcription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var optionsList: some View {
        VStack(spacing: 10) {
            ForEach(model.options, id: \.self) { option in
                Button {
                    guard verdict == nil else { return }
                    model.selectOption(option)
                } label: {
                    Text(option)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(borderColor(for: option), lineWidth: 2)
                }
                .disabled(verdict != nil)
            }
        }
    }

    /// После ответа зелёным подсвечивается правильный вариант, красным — ошибочный выбор.
    private func borderColor(for option: String) -> Color {
        guard verdict != nil, let word else { return .clear }

        let isCorrect = word.translations.contains {
            AnswerChecker.normalize($0) == AnswerChecker.normalize(option)
        }
        if isCorrect { return .green }
        return AnswerChecker.normalize(option) == AnswerChecker.normalize(model.lastInput)
            ? .red
            : .clear
    }

    private func advance() {
        autoAdvanceTask?.cancel()
        model.advanceAfterFeedback()
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
        guard case .answered(let value) = stage, value != .incorrect else { return }

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            advance()
        }
    }
}
