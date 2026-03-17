import SwiftUI

/// 设置页面（仅 macOS 端使用）
/// 将工具栏中的各种设置选项集中在此页面
#if os(macOS)
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @Binding var isPresented: Bool

    @State private var showingHotkeySettings = false
    @State private var isAccessibilityGranted = AutoPasteManager.shared.isAccessibilityGranted
    @State private var accessibilityPollTimer: Timer?

    private var l: L { settings.l }

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { settings.autoPasteOnDoubleClick && isAccessibilityGranted },
            set: { newValue in
                if newValue {
                    settings.autoPasteOnDoubleClick = true
                    AutoPasteManager.shared.requestAccessibilityIfNeeded()
                    refreshAccessibility()
                    startAccessibilityPolling()
                } else {
                    settings.autoPasteOnDoubleClick = false
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(l.settings)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 通用设置
                    settingsSection(l.generalSection) {
                        // 外观模式
                        HStack {
                            Label(l.appearance, systemImage: "circle.lefthalf.filled")
                            Spacer()
                            Picker("", selection: $settings.appearanceMode) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(settings.appearanceDisplayName(mode)).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }

                        Divider()

                        // 语言选择
                        HStack {
                            Label(l.language, systemImage: "globe")
                            Spacer()
                            Picker("", selection: $settings.appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                    }

                    // 剪贴板设置
                    settingsSection(l.clipboardSection) {
                        // 自动粘贴
                        Toggle(isOn: autoPasteBinding) {
                            Label(l.autoPasteOnDoubleClick, systemImage: "command")
                        }
                        .toggleStyle(.switch)

                        Divider()

                        // URL 双击打开浏览器
                        Toggle(isOn: $settings.openURLOnDoubleClick) {
                            Label(l.openURLOnDoubleClick, systemImage: "safari")
                        }
                        .toggleStyle(.switch)

                        Divider()

                        // 快捷键设置
                        Button {
                            showingHotkeySettings.toggle()
                        } label: {
                            HStack {
                                Label(l.hotkeySettings, systemImage: "keyboard")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingHotkeySettings, arrowEdge: .trailing) {
                            HotkeySettingsView()
                                .environmentObject(settings)
                        }
                    }

                    // 同步设置
                    settingsSection(l.syncSection) {
                        Toggle(isOn: $settings.iCloudSyncPreference) {
                            Label(l.iCloudSync, systemImage: settings.iCloudSyncPreference ? "icloud.fill" : "icloud.slash")
                        }
                        .toggleStyle(.switch)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 340, height: 420)
        .onDisappear {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
    }

    // MARK: - 辅助视图

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.3))
            }
        }
    }

    // MARK: - 辅助权限

    private func refreshAccessibility() {
        isAccessibilityGranted = AutoPasteManager.shared.isAccessibilityGranted
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let granted = AutoPasteManager.shared.isAccessibilityGranted
            if granted != isAccessibilityGranted {
                isAccessibilityGranted = granted
            }
            if granted {
                accessibilityPollTimer?.invalidate()
                accessibilityPollTimer = nil
            }
        }
    }
}
#endif
