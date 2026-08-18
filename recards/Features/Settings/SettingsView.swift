import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.newWordsPerDay) private var newWordsPerDay = SettingsDefault.newWordsPerDay
    @AppStorage(SettingsKey.reviewsPerDay) private var reviewsPerDay = SettingsDefault.reviewsPerDay
    @AppStorage(SettingsKey.blockSize) private var blockSize = SettingsDefault.blockSize
    @AppStorage(SettingsKey.recognitionEnabled) private var recognitionEnabled = SettingsDefault.recognitionEnabled
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = SettingsDefault.remindersEnabled
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = SettingsDefault.reminderHour
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = SettingsDefault.reminderMinute

    @State private var backupDocument: TextFileDocument?
    @State private var isRestoring = false
    @State private var isConfirmingReset = false
    @State private var isConfirmingWipe = false
    @State private var pendingBackup: Backup?
    @State private var message: String?
    @State private var notificationsDenied = false

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? 20
                reminderMinute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            learningSection
            soundSection
            remindersSection
            dataSection
            aboutSection
        }
        .navigationTitle("Настройки")
        .fileExporter(
            isPresented: Binding(
                get: { backupDocument != nil },
                set: { if !$0 { backupDocument = nil } }
            ),
            document: backupDocument,
            contentType: .json,
            defaultFilename: BackupService.fileName()
        ) { _ in
            backupDocument = nil
        }
        .fileImporter(isPresented: $isRestoring, allowedContentTypes: [.json]) { outcome in
            loadBackup(outcome)
        }
        .alert("Восстановить из копии?", isPresented: Binding(
            get: { pendingBackup != nil },
            set: { if !$0 { pendingBackup = nil } }
        ), presenting: pendingBackup) { backup in
            Button("Восстановить", role: .destructive) { restore(backup) }
            Button("Отмена", role: .cancel) {}
        } message: { backup in
            let words = backup.decks.reduce(0) { $0 + $1.words.count }
            Text("Текущие данные будут заменены: \(backup.decks.count) колод, \(words) слов.")
        }
        .alert("Готово", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .task { await refreshNotificationStatus() }
    }

    // MARK: - Обучение

    private var learningSection: some View {
        Section {
            Stepper("Новых слов в день: \(newWordsPerDay)", value: $newWordsPerDay, in: 1...50)
            Stepper("Повторений в день: \(reviewsPerDay)", value: $reviewsPerDay, in: 10...500, step: 10)
            Stepper("Размер блока: \(blockSize)", value: $blockSize, in: 5...50, step: 5)
            Toggle("Обратный режим", isOn: $recognitionEnabled)
        } header: {
            Text("Обучение")
        } footer: {
            Text("Обратный режим показывает слово и просит выбрать перевод из четырёх вариантов. Лимиты общие для всех активных колод.")
        }
    }

    // MARK: - Звук

    private var soundSection: some View {
        Section {
            Button("Как улучшить голоса", systemImage: "speaker.wave.3") {
                openSystemSettings()
            }
        } header: {
            Text("Звук")
        } footer: {
            Text("Слова произносятся по нажатию кнопки. Из коробки установлены упрощённые голоса; улучшенные скачиваются в системных настройках, приложение сделать это за вас не может.")
        }
    }

    // MARK: - Напоминания

    private var remindersSection: some View {
        Section {
            Toggle("Ежедневное напоминание", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, isOn in
                    Task { await handleReminderToggle(isOn) }
                }

            if remindersEnabled {
                DatePicker("Время", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderHour) { _, _ in Task { await reschedule() } }
                    .onChange(of: reminderMinute) { _, _ in Task { await reschedule() } }
            }
        } header: {
            Text("Напоминания")
        } footer: {
            if notificationsDenied {
                Text("Уведомления запрещены в системных настройках. Разрешите их, чтобы получать напоминания.")
                    .foregroundStyle(.orange)
            } else {
                Text("Напоминание приходит только в те дни, когда действительно есть что повторять.")
            }
        }
    }

    // MARK: - Данные

    private var dataSection: some View {
        Section {
            Button("Резервная копия", systemImage: "arrow.down.document") {
                makeBackup()
            }
            Button("Восстановить из копии", systemImage: "arrow.up.document") {
                isRestoring = true
            }
            Button("Сбросить весь прогресс", systemImage: "arrow.counterclockwise", role: .destructive) {
                isConfirmingReset = true
            }
            Button("Удалить все данные", systemImage: "trash", role: .destructive) {
                isConfirmingWipe = true
            }
        } header: {
            Text("Данные")
        } footer: {
            Text("Синхронизации нет: удаление приложения стирает весь прогресс. Резервная копия — единственная страховка.")
        }
        .confirmationDialog(
            "Сбросить весь прогресс?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) { resetProgress() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Слова останутся, но все карточки снова станут новыми.")
        }
        .confirmationDialog(
            "Удалить все данные?",
            isPresented: $isConfirmingWipe,
            titleVisibility: .visible
        ) {
            Button("Удалить всё", role: .destructive) { wipe() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены все колоды, слова и история. Действие необратимо.")
        }
    }

    // MARK: - О приложении

    private var aboutSection: some View {
        Section {
            Button("Язык интерфейса", systemImage: "globe") {
                openSystemSettings()
            }
            LabeledContent("Версия", value: appVersion)
        } header: {
            Text("О приложении")
        } footer: {
            Text("Язык интерфейса меняется в системных настройках приложения.")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Действия

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func handleReminderToggle(_ isOn: Bool) async {
        guard isOn else {
            NotificationService.cancelAll()
            return
        }

        let granted = await NotificationService.requestAuthorizationIfNeeded()
        notificationsDenied = !granted
        if granted {
            await NotificationService.rescheduleReminders(in: context)
        } else {
            remindersEnabled = false
        }
    }

    private func reschedule() async {
        await NotificationService.rescheduleReminders(in: context)
    }

    private func refreshNotificationStatus() async {
        guard remindersEnabled else { return }
        notificationsDenied = await NotificationService.authorizationStatus() != .authorized
    }

    private func makeBackup() {
        let backup = BackupService.makeBackup(in: context)
        guard let data = try? BackupService.encode(backup) else { return }
        backupDocument = TextFileDocument(text: String(decoding: data, as: UTF8.self))
    }

    private func loadBackup(_ outcome: Result<URL, Error>) {
        guard case .success(let url) = outcome else { return }

        let needsRelease = url.startAccessingSecurityScopedResource()
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let backup = try? BackupService.decode(data) else {
            message = "Файл не похож на резервную копию Recards."
            return
        }
        pendingBackup = backup
    }

    private func restore(_ backup: Backup) {
        do {
            try BackupService.restore(backup, into: context)
            pendingBackup = nil
            message = "Данные восстановлены."
            Task { await reschedule() }
        } catch {
            message = "Не удалось восстановить: \(error.localizedDescription)"
        }
    }

    private func resetProgress() {
        try? BackupService.resetAllProgress(in: context)
        message = "Прогресс сброшен."
    }

    private func wipe() {
        try? BackupService.deleteAll(in: context)
        NotificationService.cancelAll()
        message = "Все данные удалены."
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(PreviewData.container)
}
