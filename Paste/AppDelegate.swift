import AppKit
import ApplicationServices
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    /// 缓存主窗口引用，防止被释放后找不到
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.registerForRemoteNotifications()
        setupStatusBar()
        AutoPasteManager.shared.startTracking()

        // 延迟一帧，等 SwiftUI WindowGroup 创建完窗口后再设置 delegate
        DispatchQueue.main.async { [weak self] in
            self?.setupWindowDelegate()
            self?.setupHotkey()
        }
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

    // 点击关闭按钮时隐藏窗口而非退出应用
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // 点击 Dock 图标时重新显示窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindowFromBackground()
        }
        // 返回 false：阻止 WindowGroup 自动创建新窗口（否则会出现 2 个主窗口）
        return false
    }

    // MARK: - 窗口管理

    /// 找到 SwiftUI 创建的主窗口并设置 delegate，拦截关闭行为
    private func setupWindowDelegate() {
        guard let window = findMainWindow() else { return }
        mainWindow = window
        window.delegate = self
    }

    /// 拦截窗口关闭按钮：隐藏窗口而不是销毁
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)   // 仅隐藏，不销毁
        return false           // 阻止默认关闭行为
    }

    /// 初始化全局快捷键监听
    private func setupHotkey() {
        let manager = HotkeyManager.shared
        manager.onHotkeyTriggered = { [weak self] in
            self?.showWindowFromBackground()
        }
        manager.startListening()
    }

    // MARK: - 状态栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Paste")
            image?.isTemplate = true
            button.image = image
        }

        setupStatusMenu()
        statusItem?.menu = statusMenu
    }

    private func setupStatusMenu() {
        statusMenu = NSMenu()
        updateMenuTitles()
    }

    func updateMenuTitles() {
        guard let menu = statusMenu else { return }
        menu.removeAllItems()

        let lang = SettingsManager.shared.l

        // 打开 Paste
        let openItem = NSMenuItem(
            title: lang.openWindow,
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        // 显示窗口
        let toggleItem = NSMenuItem(
            title: lang.showWindow,
            action: #selector(showMainWindowAction),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: lang.quit,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - 菜单操作

    @objc private func openMainWindow() {
        showWindowFromBackground()
    }

    @objc private func showMainWindowAction() {
        showWindowFromBackground()
    }

    /// 从后台唤起主窗口到前台（无论窗口是被关闭、最小化、还是被遮挡）
    private func showWindowFromBackground() {
        AutoPasteManager.shared.captureFrontmostApp()

        // 先激活应用到前台（必须在操作窗口之前）
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        // 优先使用缓存的窗口引用
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            // 强制置顶：即使窗口只是被其他应用遮挡，也能提到最前
            window.orderFrontRegardless()
        } else if let window = findMainWindow() {
            mainWindow = window
            window.delegate = self
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// 在 NSApp.windows 中查找 SwiftUI 创建的主内容窗口
    private func findMainWindow() -> NSWindow? {
        return NSApp.windows.first(where: {
            $0.canBecomeMain
            && !$0.className.lowercased().contains("statusbar")
            && !$0.className.lowercased().contains("_nsalertpanel")
        })
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - 自动粘贴管理

@MainActor
final class AutoPasteManager {
    static let shared = AutoPasteManager()

    private var observer: NSObjectProtocol?
    private var lastActiveApp: NSRunningApplication?

    // MARK: - 前台应用追踪

    func startTracking() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self?.lastActiveApp = app
        }
    }

    func captureFrontmostApp() {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }
        lastActiveApp = app
    }

    // MARK: - 权限管理

    /// 检查当前是否已获得辅助功能权限
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统权限请求弹窗（仅在未授权时有效）
    func requestAccessibilityIfNeeded() {
        // 注意：使用 takeUnretainedValue() 避免重复 retain 导致野指针
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 打开系统设置的"隐私与安全 > 辅助功能"面板
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - 自动粘贴

    @discardableResult
    func performAutoPaste() -> Bool {
        // 权限不足时不执行
        let trusted = AXIsProcessTrusted()
        print("[AutoPaste] AXIsProcessTrusted = \(trusted)")
        guard trusted else { return false }

        // 优先使用追踪到的前台应用，否则从运行列表中查找
        let target: NSRunningApplication
        if let last = lastActiveApp, !last.isTerminated,
           last.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            target = last
            print("[AutoPaste] 使用追踪的目标: \(target.localizedName ?? "?") (\(target.bundleIdentifier ?? "?"))")
        } else if let fallback = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular
                && !$0.isTerminated
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }) {
            target = fallback
            print("[AutoPaste] 使用兜底目标: \(target.localizedName ?? "?") (\(target.bundleIdentifier ?? "?"))")
        } else {
            print("[AutoPaste] 无法找到目标应用，跳过")
            return false
        }

        // 隐藏 Paste 应用并将焦点移交给目标应用
        NSApp.hide(nil)
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: target)
        }
        print("[AutoPaste] 已隐藏并移交焦点，0.15s 后发送 Cmd+V")

        // 等待目标应用完全获得键盘焦点后再发送 Cmd+V（150ms 已足够）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.postPasteShortcut()
            print("[AutoPaste] Cmd+V 已发送")
        }
        return true
    }

    private static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("[AutoPaste] CGEventSource 创建失败")
            return
        }
        let keyCode: CGKeyCode = 0x09 // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
