import Foundation

/// Ключи и значения по умолчанию для настроек приложения.
///
/// Ключи объявлены в одном месте, потому что читаются с двух сторон:
/// через `@AppStorage` в интерфейсе и напрямую из `UserDefaults` в сервисах.
nonisolated enum SettingsKey {
    static let newWordsPerDay = "settings.newWordsPerDay"
    static let reviewsPerDay = "settings.reviewsPerDay"
    static let blockSize = "settings.blockSize"
    static let recognitionEnabled = "settings.recognitionEnabled"
    static let remindersEnabled = "settings.remindersEnabled"
    static let reminderHour = "settings.reminderHour"
    static let reminderMinute = "settings.reminderMinute"
}

nonisolated enum SettingsDefault {
    static let newWordsPerDay = 5
    static let reviewsPerDay = 50
    static let blockSize = 20
    static let recognitionEnabled = true
    static let remindersEnabled = false
    static let reminderHour = 20
    static let reminderMinute = 0
}

/// Чтение настроек вне интерфейса.
nonisolated enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    /// `UserDefaults` возвращает 0 для незаданного целого, поэтому ноль трактуется
    /// как «значение не сохранено» и подменяется значением по умолчанию.
    private static func integer(_ key: String, fallback: Int) -> Int {
        let value = defaults.integer(forKey: key)
        return value == 0 ? fallback : value
    }

    static var newWordsPerDay: Int {
        integer(SettingsKey.newWordsPerDay, fallback: SettingsDefault.newWordsPerDay)
    }

    static var reviewsPerDay: Int {
        integer(SettingsKey.reviewsPerDay, fallback: SettingsDefault.reviewsPerDay)
    }

    static var blockSize: Int {
        integer(SettingsKey.blockSize, fallback: SettingsDefault.blockSize)
    }

    static var recognitionEnabled: Bool {
        defaults.object(forKey: SettingsKey.recognitionEnabled) as? Bool
            ?? SettingsDefault.recognitionEnabled
    }

    static var remindersEnabled: Bool {
        defaults.object(forKey: SettingsKey.remindersEnabled) as? Bool
            ?? SettingsDefault.remindersEnabled
    }

    static var reminderTime: DateComponents {
        var components = DateComponents()
        components.hour = defaults.object(forKey: SettingsKey.reminderHour) as? Int
            ?? SettingsDefault.reminderHour
        components.minute = defaults.object(forKey: SettingsKey.reminderMinute) as? Int
            ?? SettingsDefault.reminderMinute
        return components
    }
}
