#if os(macOS)
import AppKit
import Carbon
import Combine

// MARK: - 快捷键配置模型

/// 存储用户自定义快捷键的配置
struct HotkeyConfig: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32  // Carbon modifier flags

    /// 从 NSEvent 的修饰键和 keyCode 创建
    static func from(event: NSEvent) -> HotkeyConfig? {
        let significantFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let flags = event.modifierFlags.intersection(significantFlags)
        guard !flags.isEmpty else { return nil }

        return HotkeyConfig(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(from: flags)
        )
    }

    /// 生成人类可读的快捷键文本，例如 "⌘⇧V"
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(UInt16(keyCode)))
        return parts.joined()
    }

    /// 将 NSEvent.ModifierFlags 转换为 Carbon modifier flags
    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

// MARK: - 全局快捷键管理器（基于 Carbon RegisterEventHotKey）

/// 使用 Carbon API 注册全局热键，无需辅助功能权限
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    // MARK: - UserDefaults 键名

    private let keyCodeKey = "hotkeyKeyCode"
    private let modifiersKey = "hotkeyModifiers"

    // MARK: - 状态

    /// 当前配置的快捷键（nil 表示未设置）
    @Published var currentHotkey: HotkeyConfig?
    /// 快捷键触发时的回调
    var onHotkeyTriggered: (() -> Void)?

    // MARK: - Carbon 热键引用

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// 用于 Carbon 回调中访问 Swift 实例的全局指针
    private static var sharedInstance: HotkeyManager?

    // MARK: - 初始化

    private init() {
        HotkeyManager.sharedInstance = self
        loadFromDefaults()
    }

    // MARK: - 公开接口

    /// 设置新的快捷键
    func setHotkey(_ config: HotkeyConfig) {
        currentHotkey = config
        saveToDefaults(config)
        registerCarbonHotkey()
    }

    /// 清除快捷键
    func clearHotkey() {
        unregisterCarbonHotkey()
        currentHotkey = nil
        clearDefaults()
    }

    /// 启动监听（应用启动时调用）
    func startListening() {
        if currentHotkey != nil {
            registerCarbonHotkey()
        }
    }

    // MARK: - 持久化

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeKey) != nil else { return }

        let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
        let modifiers = UInt32(defaults.integer(forKey: modifiersKey))

        guard modifiers != 0 else { return }

        currentHotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
    }

    private func saveToDefaults(_ config: HotkeyConfig) {
        let defaults = UserDefaults.standard
        defaults.set(Int(config.keyCode), forKey: keyCodeKey)
        defaults.set(Int(config.modifiers), forKey: modifiersKey)
    }

    
    private func clearDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keyCodeKey)
        defaults.removeObject(forKey: modifiersKey)
    }

    // MARK: - Carbon 热键注册

    /// 注册全局热键（使用 Carbon API，无需辅助功能权限）
    private func registerCarbonHotkey() {
        unregisterCarbonHotkey()

        guard let hotkey = currentHotkey else { return }

        // 1. 安装 Carbon 事件处理器
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            // 从 Carbon 回调中触发 Swift 回调
            DispatchQueue.main.async {
                HotkeyManager.sharedInstance?.onHotkeyTriggered?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // 2. 注册热键
        let hotkeyID = EventHotKeyID(
            signature: OSType(0x50535445),  // "PSTE" 的 ASCII
            id: 1
        )

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            self.hotkeyRef = hotKeyRef
            #if DEBUG
            print("全局热键注册成功: \(hotkey.displayString)")
            #endif
        } else {
            #if DEBUG
            print("全局热键注册失败，错误码: \(status)")
            #endif
        }
    }

    /// 注销全局热键
    private func unregisterCarbonHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}

// MARK: - 辅助函数：keyCode 转可读字符串

private func keyCodeToString(_ keyCode: UInt16) -> String {
    let keyMap: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "8", 0x19: "7",
        0x1A: "9", 0x1C: "0",
        0x1D: "]", 0x1E: "P", 0x1F: "[",
        0x20: "U", 0x21: "I", 0x22: "O", 0x23: "L",
        0x25: "J", 0x26: "K",
        0x28: "N", 0x29: "M",
        0x2C: "/", 0x2F: ".",
        0x24: "↩", 0x30: "⇥", 0x31: "␣", 0x33: "⌫",
        0x35: "⎋", 0x39: "⇪",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]

    return keyMap[keyCode] ?? "Key(\(keyCode))"
}
#endif
