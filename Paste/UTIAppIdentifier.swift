import Foundation
#if os(iOS)
import UIKit
#endif

/// 通过剪贴板 UTI 类型推断来源 App
enum UTIAppIdentifier {

    /// 从 pasteboard.types 推断来源 App
    /// - Parameter types: UIPasteboard.general.types
    /// - Returns: 推断出的来源信息，无法识别时返回 nil
    static func inferSourceApp(from types: [String]) -> SourceApplicationInfo? {
        // 过滤标准系统 UTI，只保留可能标识来源 App 的类型
        let candidateTypes = types.filter { type in
            !type.hasPrefix("public.") &&
            !type.hasPrefix("com.apple.uikit.") &&
            !type.hasPrefix("Apple ") &&
            !type.hasPrefix("com.apple.pboard.") &&
            !type.hasPrefix("NSString") &&
            !type.hasPrefix("com.apple.flat-rtfd") &&
            type != "com.apple.pasteboard.promised-file-url"
        }

        for type in candidateTypes {
            let lower = type.lowercased()
            for (prefix, info) in utiPrefixMap {
                if lower.hasPrefix(prefix) {
                    return info
                }
            }
        }

        // Safari 特殊处理
        if types.contains("com.apple.mobilesafari.url") ||
            types.contains("com.apple.safari.url") ||
            types.contains(where: { $0.lowercased().contains("weburl") }) {
            return SourceApplicationInfo(name: "Safari", bundleID: "com.apple.mobilesafari")
        }

        return nil
    }

    // MARK: - UTI 前缀映射表

    private static let utiPrefixMap: [(String, SourceApplicationInfo)] = [
        // 社交 / 通讯
        ("com.tencent.xin",        SourceApplicationInfo(name: "WeChat", bundleID: "com.tencent.xin")),
        ("com.tencent.mqq",        SourceApplicationInfo(name: "QQ", bundleID: "com.tencent.mqq")),
        ("com.tencent.qq",         SourceApplicationInfo(name: "QQ", bundleID: "com.tencent.mqq")),
        ("ph.telegra.",            SourceApplicationInfo(name: "Telegram", bundleID: "ph.telegra.Telegraph")),
        ("org.telegram.",          SourceApplicationInfo(name: "Telegram", bundleID: "ph.telegra.Telegraph")),
        ("com.facebook.",          SourceApplicationInfo(name: "Facebook", bundleID: "com.facebook.Facebook")),
        ("com.twitter.",           SourceApplicationInfo(name: "X", bundleID: "com.atebits.Tweetie2")),
        ("com.whatsapp.",          SourceApplicationInfo(name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp")),
        ("net.whatsapp.",          SourceApplicationInfo(name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp")),
        ("com.linkedin.",          SourceApplicationInfo(name: "LinkedIn", bundleID: "com.linkedin.LinkedIn")),
        ("com.skype.",             SourceApplicationInfo(name: "Skype", bundleID: "com.skype.skype")),
        ("com.discord.",           SourceApplicationInfo(name: "Discord", bundleID: "com.hammerandchisel.discord")),

        // 浏览器
        ("org.chromium.",          SourceApplicationInfo(name: "Chrome", bundleID: "com.google.chrome.ios")),
        ("com.google.chrome.",     SourceApplicationInfo(name: "Chrome", bundleID: "com.google.chrome.ios")),
        ("org.mozilla.",           SourceApplicationInfo(name: "Firefox", bundleID: "org.mozilla.ios.Firefox")),
        ("com.microsoft.msedge.",  SourceApplicationInfo(name: "Edge", bundleID: "com.microsoft.msedge")),
        ("com.brave.",             SourceApplicationInfo(name: "Brave", bundleID: "com.brave.ios.browser")),
        ("com.operasoftware.",     SourceApplicationInfo(name: "Opera", bundleID: "com.opera.OperaTouch")),

        // 办公 / 笔记
        ("com.microsoft.word.",    SourceApplicationInfo(name: "Word", bundleID: "com.microsoft.Office.Word")),
        ("com.microsoft.excel.",   SourceApplicationInfo(name: "Excel", bundleID: "com.microsoft.Office.Excel")),
        ("com.microsoft.powerpoint.", SourceApplicationInfo(name: "PowerPoint", bundleID: "com.microsoft.Office.Powerpoint")),
        ("com.microsoft.onenote.", SourceApplicationInfo(name: "OneNote", bundleID: "com.microsoft.onenote")),
        ("com.microsoft.office.",  SourceApplicationInfo(name: "Microsoft Office", bundleID: "com.microsoft.Office")),
        ("com.notion.",            SourceApplicationInfo(name: "Notion", bundleID: "notion.id")),

        // 开发工具
        ("com.apple.dt.xcode.",    SourceApplicationInfo(name: "Xcode", bundleID: "com.apple.dt.Xcode")),
        ("com.apple.dt.",          SourceApplicationInfo(name: "Xcode", bundleID: "com.apple.dt.Xcode")),
        ("com.googlecode.iterm2.", SourceApplicationInfo(name: "iTerm", bundleID: "com.googlecode.iterm2")),
        ("com.microsoft.vscode.",  SourceApplicationInfo(name: "VS Code", bundleID: "com.microsoft.VSCode")),
        ("vscode-editor-data",     SourceApplicationInfo(name: "VS Code", bundleID: "com.microsoft.VSCode")),
    ]
}
