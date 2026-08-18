import SwiftUI
import SwiftData

/// Главный экран: сводка по активным колодам и вход в оба режима.
struct HomeView: View {
    @Environment(\.modelContext) private var context

    // Запросы существуют ради перерисовки: при изменении слов и карточек
    // счётчики должны пересчитываться сами.
    @Query private var decks: [Deck]
    @Query private var cards: [ReCard]

    @State private var activeSession: SessionMode?
    /// Сколько новых слов разрешено взять сверх дневной нормы в открываемой сессии.
    @State private var additionalNewWords = 0

    private var summary: SessionService.Summary {
        SessionService.summary(in: context)
    }

    var body: some View {
        Group {
            if summary.hasDecks {
                content
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

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                counters

                if summary.canLearn || summary.canReview {
                    actions
                } else {
                    allDoneCard
                }
            }
            .padding(20)
        }
    }

    private var counters: some View {
        HStack(spacing: 12) {
            counter(summary.newAvailable, title: "новых", color: .blue)
            counter(summary.dueNow, title: "к повторению", color: .orange)
            counter(summary.learned, title: "выучено", color: .green)
        }
    }

    private func counter(_ value: Int, title: String, color: Color) -> some View {
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

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                activeSession = .review
            } label: {
                actionLabel(
                    title: "Повторить",
                    subtitle: summary.dueNow > 0
                        ? "\(summary.dueNow) карточек готовы"
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

    private func actionLabel(title: String, subtitle: String, systemImage: String) -> some View {
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
    private var allDoneCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("На сегодня всё")
                .font(.title3.bold())

            Text(nextDueDescription)
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

    private var nextDueDescription: String {
        guard let next = summary.nextDue else {
            return "Новых повторений пока не запланировано."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Следующее повторение \(formatter.localizedString(for: next, relativeTo: Date()))."
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
