import SwiftUI

/// 设置页面
/// 将工具栏中的各种设置选项集中在此页面
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var autoPaste = AutoPasteManager.shared
    @Binding var isPresented: Bool

    @State private var showingHotkeySettings = false

    private var l: L { settings.l }

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { settings.autoPasteOnDoubleClick && autoPaste.isAccessibilityGranted },
            set: { newValue in
                if newValue {
                    settings.autoPasteOnDoubleClick = true
                    autoPaste.requestAccessibilityIfNeeded()
                } else {
                    settings.autoPasteOnDoubleClick = false
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PasteTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(PasteTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(l.settings)
                        .font(.system(size: 21, weight: .semibold))
                    Text(l.appTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(l.done) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 通用设置
                    settingsSection(l.generalSection) {
                        // 外观模式
                        HStack(spacing: 12) {
                            settingLabel(l.appearance, systemImage: "circle.lefthalf.filled")
                            Spacer()
                            Picker("", selection: $settings.appearanceMode) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(settings.appearanceDisplayName(mode)).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityLabel(l.appearance)
                            .frame(width: 120)
                        }
                        .frame(minHeight: 40)

                        sectionDivider

                        // 语言选择
                        HStack(spacing: 12) {
                            settingLabel(l.language, systemImage: "globe")
                            Spacer()
                            Picker("", selection: $settings.appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityLabel(l.language)
                            .frame(width: 120)
                        }
                        .frame(minHeight: 40)
                    }

                    // 剪贴板设置
                    settingsSection(l.clipboardSection) {
                        // 自动粘贴
                        Toggle(isOn: autoPasteBinding) {
                            settingLabel(l.autoPasteOnDoubleClick, systemImage: "command")
                        }
                        .toggleStyle(.switch)
                        .frame(minHeight: 44)
                        .help(l.autoPasteOnDoubleClickHint)

                        sectionDivider

                        // URL 双击打开浏览器
                        Toggle(isOn: $settings.openURLOnDoubleClick) {
                            settingLabel(l.openURLOnDoubleClick, systemImage: "safari")
                        }
                        .toggleStyle(.switch)
                        .frame(minHeight: 44)

                        sectionDivider

                        // 快捷键设置
                        Button {
                            showingHotkeySettings.toggle()
                        } label: {
                            HStack(spacing: 12) {
                                settingLabel(l.hotkeySettings, systemImage: "keyboard")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 4)
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
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
                            settingLabel(l.iCloudSync, systemImage: settings.iCloudSyncPreference ? "icloud.fill" : "icloud.slash")
                        }
                        .toggleStyle(.switch)
                        .frame(minHeight: 40)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .tint(PasteTheme.accent)
        .frame(width: 392, height: 520)
        .background(PasteTheme.canvas)
        .onDisappear {
            autoPaste.stopAccessibilityPolling()
        }
    }

    // MARK: - 辅助视图

    private var sectionDivider: some View {
        Divider()
            .opacity(0.6)
            .padding(.leading, 40)
    }

    private func settingLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PasteTheme.accent)
                .frame(width: 28, height: 28)
                .background(PasteTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 3)

            VStack(alignment: .leading, spacing: 2) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(PasteTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(PasteTheme.border.opacity(0.7), lineWidth: 1)
                    }
            }
        }
    }
}
