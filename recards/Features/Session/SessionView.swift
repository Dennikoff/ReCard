import SwiftUI
import SwiftData

/// Контейнер сессии: шапка с прогрессом и текущий экран в зависимости от стадии.
///
/// Открывается модально поверх всего интерфейса. Свайпа назад здесь намеренно нет:
/// случайный жест не должен выкидывать из упражнения.
struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SessionViewModel
    @State private var isConfirmingExit = false

    init(mode: SessionMode, context: ModelContext, deck: Deck? = nil, additionalNewWords: Int = 0) {
        _model = State(initialValue: SessionViewModel(
            mode: mode,
            context: context,
            deck: deck,
            additionalNewWords: additionalNewWords
        ))
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                content
            }
        }
        .confirmationDialog(
            "Выйти из сессии?",
            isPresented: $isConfirmingExit,
            titleVisibility: .visible
        ) {
            Button("Выйти", role: .destructive) { dismiss() }
            Button("Продолжить", role: .cancel) {}
        } message: {
            Text("Отвеченные карточки уже сохранены. Остальные придут в следующий раз.")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.18), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var header: some View {
        if case .finished = model.stage {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Button {
                    isConfirmingExit = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(10)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Закрыть сессию")

                ProgressView(value: model.progressValue)
                    .tint(.accentColor)

                Text(model.progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .introducing, .reading:
            NewWordView(model: model)

        case .asking, .answered:
            if model.currentDirection == .recognition {
                RecognitionCardView(model: model)
            } else {
                ProductionCardView(model: model)
            }

        case .blockBreak:
            BlockBreakView(model: model) { dismiss() }

        case .finished:
            SessionResultView(model: model) { dismiss() }
                .task { await finishSession() }
        }
    }

    /// Разрешение на уведомления запрашивается здесь, а не при первом запуске:
    /// к этому моменту пользователь уже понимает, о чём его будут напоминать.
    private func finishSession() async {
        guard model.totalAnswered > 0 else { return }

        let context = model.modelContext
        if !UserDefaults.standard.bool(forKey: Self.didAskForNotificationsKey) {
            UserDefaults.standard.set(true, forKey: Self.didAskForNotificationsKey)
            let granted = await NotificationService.requestAuthorizationIfNeeded()
            if granted {
                UserDefaults.standard.set(true, forKey: SettingsKey.remindersEnabled)
            }
        }
        await NotificationService.rescheduleReminders(in: context)
    }

    private static let didAskForNotificationsKey = "notifications.didAsk"
}

// MARK: - Передышка между блоками

private struct BlockBreakView: View {
    let model: SessionViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Блок пройден")
                    .font(.title2.bold())
                Text("Верно \(model.correctCount) · с ошибкой \(model.incorrectCount)")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    model.startNextBlock()
                } label: {
                    Text("Продолжить")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Выйти", action: onExit)
                    .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}
