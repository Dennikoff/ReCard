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
        }
        .modelContainer(container)
    }
}
