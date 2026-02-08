//
//  PasteApp.swift
//  Paste
//
//  Created by 黄尧栋 on 2026/2/8.
//

import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClipboardStore(persistence: PersistenceController.shared)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .task {
                    store.start()
                }
        }
    }
}
