import SwiftUI

/// Знакомство с новым словом.
///
/// «Знаю» не принимается на веру: приложение просит подтвердить ответ печатью.
/// Без этого самообман обесценивает весь дальнейший расчёт интервалов.
struct NewWordView: View {
    let model: SessionViewModel

    private var word: Word? { model.currentWord }
    private var isRevealed: Bool { model.stage == .reading }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            card

            if isRevealed {
                Button {
                    model.continueAfterReading()
                } label: {
                    Text("Дальше")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                choiceButtons
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .animation(.snappy, value: model.stage)
    }

    private var card: some View {
        VStack(spacing: 12) {
            Text("Новое слово")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Text(word?.text ?? "")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)

                if isRevealed {
                    Button {
                        model.speakCurrentWord()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Произнести слово")
                }
            }

            if isRevealed {
                revealedContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var revealedContent: some View {
        VStack(spacing: 10) {
            if let transcription = word?.transcription {
                Text(transcription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(word?.translations.joined(separator: ", ") ?? "")
                .font(.title3)

            if let example = word?.example {
                VStack(spacing: 3) {
                    Text(example).font(.callout)
                    if let translation = word?.exampleTranslation {
                        Text(translation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var choiceButtons: some View {
        VStack(spacing: 12) {
            Button {
                model.claimKnown()
            } label: {
                Text("Знаю")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                model.revealNewWord()
            } label: {
                Text("Не знаю")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("«Знаю» нужно будет подтвердить: приложение попросит напечатать слово.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
