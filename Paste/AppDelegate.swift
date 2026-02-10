import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.registerForRemoteNotifications()
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        let anyUserInfo = userInfo.reduce(into: [AnyHashable: Any]()) { result, pair in
            result[AnyHashable(pair.key)] = pair.value
        }
        _ = PersistenceController.shared.handleRemoteNotification(anyUserInfo)
    }
}
