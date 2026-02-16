import SwiftUI
import CoreData
import Combine
#if os(iOS)
import UIKit
#endif

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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runtime.store)
                .environmentObject(runtime.settings)
                .environmentObject(runtime)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .preferredColorScheme(runtime.settings.appearanceMode.colorScheme)
        }
    }
}

#if os(iOS)
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let handled = PersistenceController.shared.handleRemoteNotification(userInfo)
        completionHandler(handled ? .newData : .noData)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
}
#endif
