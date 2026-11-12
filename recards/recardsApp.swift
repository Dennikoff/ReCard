import SwiftUI
import SwiftData

@main
struct RecardsApp: App {
    /// Схема хранилища. Модели совместимы с CloudKit (все свойства имеют значения
    /// по умолчанию, ограничений уникальности нет), чтобы синхронизацию можно было
    /// включить позже без миграции.
    private let container: ModelContainer = {
        let schema = Schema([Deck.self, Word.self, ReCard.self, ReLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Не удалось создать хранилище: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // Юнит-тесты запускают это же приложение как хост. Стартовые
                    // побочные эффекты (уведомления, наполнение базы) в тестах не нужны
                    // и мешают, поэтому под тестами пропускаются.
                    guard !Self.isRunningTests else { return }
                    let context = container.mainContext
                    CardMigration.removeRecognitionCards(in: context)
                    DemoDeckLoader.loadIfNeeded(into: context)
                    await NotificationService.rescheduleReminders(in: context)
                }
        }
        .modelContainer(container)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
