import SwiftUI

/// Итоги сессии: счёт и слова, на которых пользователь споткнулся.
struct SessionResultView: View {
    let model: SessionViewModel
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.totalAnswered == 0 {
                emptyState
            } else {
                summary
            }

            Button(action: onFinish) {
                Text("Готово")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нечего повторять", systemImage: "checkmark.circle")
        } description: {
            Text("Все карточки на сегодня уже пройдены.")
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 32)

                Image(systemName: model.incorrectCount == 0 ? "star.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(model.incorrectCount == 0 ? .yellow : .green)

                Text(model.incorrectCount == 0 ? "Без единой ошибки" : "Сессия завершена")
                    .font(.title2.bold())

                HStack(spacing: 28) {
                    counter(model.correctCount, label: "верно", color: .green)
                    counter(model.incorrectCount, label: "с ошибкой", color: .red)
                }

                if !model.mistakes.isEmpty {
                    mistakesList
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func counter(_ value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mistakesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Стоит повторить")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(model.mistakes) { mistake in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mistake.word)
                            .font(.body)
                        Text(mistake.expected)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        model.speak(mistake.word, language: mistake.language)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Произнести слово")
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
        .padding(.top, 8)
    }
}
