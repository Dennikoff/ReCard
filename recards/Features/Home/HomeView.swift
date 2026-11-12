import SwiftUI
import SwiftData

/// Главный экран: сводка по активным колодам и вход в оба режима.
struct HomeView: View {
    @Environment(\.modelContext) private var context

    // Запросы существуют ради перерисовки: при изменении слов и карточек
    // счётчики должны пересчитываться сами.
    @Query private var decks: [Deck]
    @Query private var cards: [ReCard]

    #if DEBUG
    // Тоже ради перерисовки: перемотка времени в настройках меняет,
    // какие карточки уже пора повторять.
    @AppStorage(AppClock.offsetKey) private var clockOffset = 0.0
    #endif

    @State private var activeSession: SessionMode?
    /// Сколько новых слов разрешено взять сверх дневной нормы в открываемой сессии.
    @State private var additionalNewWords = 0

    var body: some View {
        // Пока экран на виду, сводка пересчитывается раз в секунду: карточки
        // становятся доступны с течением времени, а не при изменении данных.
        // Считается один раз за тик и передаётся вниз — каждый расчёт делает выборки.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let summary = SessionService.summary(in: context)
            if summary.hasDecks {
                content(summary)
            } else {
                emptyState
            }
        }
        .navigationTitle("Учить")
        .fullScreenCover(item: $activeSession, onDismiss: { additionalNewWords = 0 }) { mode in
            SessionView(mode: mode, context: context, additionalNewWords: additionalNewWords)
        }
    }

    // MARK: - Основное содержимое

    private func content(_ summary: SessionService.Summary) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                counters(summary)

                if summary.canLearn || summary.canReview {
                    actions(summary)
                } else {
                    allDoneCard(summary)
                }
            }
            .padding(20)
        }
    }

    private func counters(_ summary: SessionService.Summary) -> some View {
        HStack(spacing: 12) {
            counter(summary.newAvailable, title: "новых", color: .blue)
            counter(summary.dueNow, title: "к повторению", color: .orange)
            counter(summary.learned, title: "выучено", color: .green)
        }
    }

    private func counter(_ value: Int, title: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func actions(_ summary: SessionService.Summary) -> some View {
        VStack(spacing: 12) {
            Button {
                activeSession = .review
            } label: {
                actionLabel(
                    title: "Повторить",
                    subtitle: summary.dueNow > 0
                        ? "\(summary.dueNow) слов ждут повторения"
                        : "Пока нечего повторять",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!summary.canReview)

            Button {
                additionalNewWords = 0
                activeSession = .learn
            } label: {
                actionLabel(
                    title: "Изучить новые",
                    subtitle: summary.newAvailable > 0
                        ? "\(summary.newAvailable) слов доступно сегодня"
                        : "Дневная норма выполнена",
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!summary.canLearn)
        }
    }

    private func actionLabel(title: LocalizedStringKey, subtitle: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.8)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    /// Состояние «на сегодня всё»: не навязываем продолжение, но и не запрещаем.
    private func allDoneCard(_ summary: SessionService.Summary) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("На сегодня всё")
                .font(.title3.bold())

            Text(nextDueDescription(summary))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if hasUnstartedWords {
                Button("Взять ещё \(AppSettings.newWordsPerDay) новых слов") {
                    additionalNewWords = AppSettings.newWordsPerDay
                    activeSession = .learn
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var hasUnstartedWords: Bool {
        SessionService.activeDecks(in: context)
            .flatMap(\.sortedWords)
            .contains(where: \.isNew)
    }

    /// `LocalizedStringKey`, а не `String`: иначе фраза не переводится.
    private func nextDueDescription(_ summary: SessionService.Summary) -> LocalizedStringKey {
        guard let next = summary.nextDue else {
            return "Новых повторений пока не запланировано."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Следующее повторение \(formatter.localizedString(for: next, relativeTo: AppClock.now))."
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет активных колод", systemImage: "graduationcap")
        } description: {
            Text("Создайте колоду на вкладке «Колоды» или включите существующую.")
        }
    }
}

extension SessionMode: Identifiable {
    public var id: Int {
        switch self {
        case .review: return 0
        case .learn: return 1
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.container)
}
