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
                    PlaceholderView(title: "Настройки")
                        .navigationTitle("Настройки")
                }
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(
            "Раздел «\(title)»",
            systemImage: "hammer",
            description: Text("Появится на следующем этапе.")
        )
    }
}

#Preview {
    RootView()
}
