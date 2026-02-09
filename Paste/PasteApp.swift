import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClipboardStore(persistence: PersistenceController.shared)
    @StateObject private var settings = SettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
                .task {
                    store.start()
                }
        }
    }
}
