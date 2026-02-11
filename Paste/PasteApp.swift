import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClipboardStore(persistence: PersistenceController.shared)
    private var settings: SettingsManager { SettingsManager.shared }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .task {
                    store.start()
                }
        }
    }
}
