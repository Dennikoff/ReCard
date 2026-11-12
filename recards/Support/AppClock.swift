import Foundation

/// Источник «текущего момента» для логики обучения: сроки карточек,
/// дневные лимиты, журнал ответов.
///
/// В релизной сборке это просто `Date()`. В отладочной к реальному времени
/// прибавляется сдвиг из настроек — так на демо можно «перемотать» дни
/// и увидеть, как карточки возвращаются на повторение.
///
/// Реальное время по-прежнему нужно там, где важен физический момент:
/// замер скорости ответа, расписание системных уведомлений, имя файла копии.
nonisolated enum AppClock {
    static var now: Date {
        #if DEBUG
        Date().addingTimeInterval(offset)
        #else
        Date()
        #endif
    }

    #if DEBUG
    static let offsetKey = "debug.clockOffset"

    /// Сдвиг в секундах относительно реального времени.
    /// Под тестами всегда ноль: сдвиг, оставшийся в симуляторе после демо,
    /// не должен влиять на результаты.
    static var offset: TimeInterval {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return 0 }
        return UserDefaults.standard.double(forKey: offsetKey)
    }
    #endif
}
