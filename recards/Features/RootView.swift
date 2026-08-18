import SwiftUI

/// Корневая навигация приложения.
///
/// Вкладки — заглушки: содержимое появляется на следующих этапах.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Учить", systemImage: "graduationcap") {
                NavigationStack {
                    HomeView()
                }
            }

            Tab("Колоды", systemImage: "rectangle.stack") {
                NavigationStack {
                    DecksView()
                }
            }

            Tab("Настройки", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

#Preview {
    RootView()
}
