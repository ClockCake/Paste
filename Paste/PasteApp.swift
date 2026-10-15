import SwiftUI
import CoreData
import Combine

@MainActor
final class AppRuntime: ObservableObject {
    @Published private(set) var store: ClipboardStore
    let settings: SettingsManager

    init() {
        settings = SettingsManager.shared
        store = ClipboardStore(persistence: PersistenceController.shared)
        store.start()
    }

    func applyICloudPreferenceChange() {
        store.stop()
        PersistenceController.reloadShared()
        let refreshedStore = ClipboardStore(persistence: PersistenceController.shared)
        refreshedStore.start()
        store = refreshedStore
    }
}

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runtime.store)
                .environmentObject(runtime.settings)
                .environmentObject(runtime)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        }
        // 使用原生交通灯和拖动区域，内容区承载搜索与分类。
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
    }
}
