import Foundation
import SwiftData
import UserNotifications

/// Локальные напоминания о повторении.
///
/// Ни сервера, ни push-сертификатов: всё планируется на устройстве.
@MainActor
enum NotificationService {

    private static let identifierPrefix = "recards.reminder."
    /// На сколько дней вперёд планируются напоминания.
    private static let horizonDays = 7

    // MARK: - Разрешение

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Запрашивает разрешение, если оно ещё не запрашивалось.
    ///
    /// Вызывается **после первой завершённой сессии**, а не при запуске: запрос,
    /// смысл которого пользователь ещё не понял, получает отказ и второго шанса не даёт.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    // MARK: - Планирование

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (0..<horizonDays).map { "\(identifierPrefix)\($0)" }
        )
    }

    /// Перестраивает расписание напоминаний на ближайшие дни.
    ///
    /// Повторяющееся уведомление не может знать, сколько карточек созреет, и не умеет
    /// молчать в пустой день. Поэтому вместо одного повторяющегося планируется несколько
    /// одиночных — по числу дней, в которые действительно есть что повторять.
    static func rescheduleReminders(in context: ModelContext, now: Date = Date()) async {
        cancelAll()

        guard AppSettings.remindersEnabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        let calendar = Calendar.current
        let time = AppSettings.reminderTime

        // Карточки, не выведенные из ротации: их сроки и определяют дни напоминаний.
        let dueDates = SessionService.activeDecks(in: context)
            .flatMap(\.sortedWords)
            .flatMap { $0.cards ?? [] }
            .filter { !$0.isArchived }
            .map(\.due)

        guard !dueDates.isEmpty else { return }

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(
                    bySettingHour: time.hour ?? 20,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: day
                  ),
                  fireDate > now
            else { continue }

            let count = dueDates.count { $0 <= fireDate }
            guard count > 0 else { continue }

            schedule(at: fireDate, count: count, index: offset, calendar: calendar)
        }
    }

    private static func schedule(at date: Date, count: Int, index: Int, calendar: Calendar) {
        let content = UNMutableNotificationContent()
        content.title = "Пора повторить"
        content.body = "Готово к повторению: \(count) карточек."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)\(index)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
