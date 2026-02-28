import SwiftUI
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingClearAllAlert = false
    @State private var showingCloudErrorAlert = false
    #if os(iOS)
    @State private var showingPastePermissionAlert = false
    @AppStorage("didShowPastePermissionGuide") private var didShowPastePermissionGuide = false
    #endif
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @State private var showingHotkeySettings = false
    @State private var showingAccessibilityAlert = false
    @State private var selectedCardForDetail: ClipboardCard?
    @State private var nowTick = Date()
    @FocusState private var isSearchFocused: Bool

    private var l: L { settings.l }
    private var cloudSyncStatusText: String {
        if store.cloudSyncErrorMessage != nil { return l.iCloudSyncFailed }
        if !store.cloudSyncEnabled { return l.iCloudOff }
        if store.cloudSyncInProgress { return l.iCloudSyncing }
        return l.iCloudOn
    }
    private var cloudSyncStatusSymbol: String {
        if store.cloudSyncErrorMessage != nil { return "exclamationmark.triangle.fill" }
        if !store.cloudSyncEnabled { return "icloud.slash" }
        return "icloud.fill"
    }
    private var cloudSyncStatusTint: Color {
        if store.cloudSyncErrorMessage != nil { return .orange }
        if !store.cloudSyncEnabled { return .secondary }
        if store.cloudSyncInProgress { return .blue }
        return .primary
    }
    private var cloudSyncStatusBackground: Color {
        if store.cloudSyncErrorMessage != nil { return .orange.opacity(0.16) }
        if store.cloudSyncInProgress { return .blue.opacity(0.12) }
        return .secondary.opacity(0.16)
    }
    private var cloudLastSyncedText: String? {
        guard store.cloudSyncEnabled else { return nil }
        guard let lastSyncDate = store.lastSuccessfulCloudSyncDate else {
            return l.iCloudNotSyncedYet
        }
        return l.iCloudLastSynced(l.relativeTimeSince(lastSyncDate, now: nowTick))
    }

    var body: some View {
        rootLayout
        .alert(l.clearAllConfirmTitle, isPresented: $showingClearAllAlert) {
            Button(l.cancel, role: .cancel) {}
            Button(l.clear, role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text(l.clearAllConfirmMessage)
        }
        .alert(l.iCloudErrorTitle, isPresented: $showingCloudErrorAlert) {
            Button("OK") {}
        } message: {
            Text(store.cloudSyncErrorMessage ?? l.iCloudErrorUnknown)
        }
        #if os(iOS)
        .alert(l.pastePermissionTitle, isPresented: $showingPastePermissionAlert) {
            Button(l.openSystemSettings) {
                openPastePermissionSettings()
            }
            Button(l.cancel, role: .cancel) {}
        } message: {
            Text(l.pastePermissionMessage)
        }
        #endif
        #if os(macOS)
        .alert(l.accessibilityPermissionTitle, isPresented: $showingAccessibilityAlert) {
            Button(l.openSystemSettings) {
                AutoPasteManager.shared.openAccessibilitySettings()
            }
            Button(l.cancel, role: .cancel) {
                settings.autoPasteOnDoubleClick = false
            }
        } message: {
            Text(l.accessibilityPermissionMessage)
        }
        #endif
        .task {
            selectedFilter = store.currentFilter
            selectedTimeFilter = store.currentTimeFilter
            #if os(iOS)
            if !didShowPastePermissionGuide {
                didShowPastePermissionGuide = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showingPastePermissionAlert = true
                }
            }
            #endif
            #if os(macOS)
            NSApp.appearance = settings.appearanceMode.nsAppearance
            if settings.autoPasteOnDoubleClick {
                ensureAccessibilityPermission(showFallbackAlert: false)
            }
            #endif
        }
        .onChange(of: settings.appearanceMode) { newValue in
            #if os(macOS)
            NSApp.appearance = newValue.nsAppearance
            #endif
        }
        .onChange(of: selectedFilter) { newValue in
            DispatchQueue.main.async {
                store.updateFilter(newValue)
            }
        }
        .onChange(of: searchText) { newValue in
            DispatchQueue.main.async {
                store.updateSearch(newValue)
            }
        }
        .onChange(of: selectedTimeFilter) { newValue in
            DispatchQueue.main.async {
                store.updateTimeFilter(newValue)
            }
        }
        .onChange(of: ObjectIdentifier(store)) { _ in
            DispatchQueue.main.async {
                store.updateFilter(selectedFilter)
                store.updateSearch(searchText)
                store.updateTimeFilter(selectedTimeFilter)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            nowTick = date
        }
        #if os(iOS)
        .sheet(item: $selectedCardForDetail) { card in
            ClipboardDetailSheet(card: card)
                .environmentObject(store)
                .environmentObject(settings)
        }
        #endif
    }

    @ViewBuilder
    private var rootLayout: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
            headerView
            filterBar
            cardArea
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        #else
        VStack(alignment: .leading, spacing: 16) {
            headerView
            filterBar
            cardArea
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 520)
        #endif
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.appTitle)
                        .font(.title.weight(.bold))
                    Text(l.appSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                toolbarButtons
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Label(l.itemCount(store.totalItems), systemImage: "tray.full")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        )

                    Label(store.storageText, systemImage: "externaldrive")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        )

                    cloudSyncStatusBadge

                    if let syncedText = cloudLastSyncedText {
                        Label(syncedText, systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.quaternary.opacity(0.5))
                            )
                    }
                }
                .padding(.vertical, 1)
            }
        }
        #else
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.appTitle)
                    .font(.largeTitle.weight(.bold))
                Text(l.appSubtitle)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text(l.itemCount(store.totalItems))
                    Text(store.storageText)
                    cloudSyncStatusInline
                    if let syncedText = cloudLastSyncedText {
                        Text(syncedText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            toolbarButtons
        }
        #endif
    }

    // MARK: - Toolbar

    private var appearanceIcon: String {
        switch settings.appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    @ViewBuilder
    private var cloudSyncStatusBadge: some View {
        if store.cloudSyncErrorMessage != nil {
            Button {
                showingCloudErrorAlert = true
            } label: {
                cloudSyncStatusLabel
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(cloudSyncStatusBackground)
                    )
            }
            .buttonStyle(.plain)
            .platformHelp(l.iCloudErrorHint)
        } else {
            cloudSyncStatusLabel
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(cloudSyncStatusBackground)
                )
        }
    }

    @ViewBuilder
    private var cloudSyncStatusInline: some View {
        if store.cloudSyncErrorMessage != nil {
            Button {
                showingCloudErrorAlert = true
            } label: {
                cloudSyncStatusLabel
            }
            .buttonStyle(.plain)
            .platformHelp(l.iCloudErrorHint)
        } else {
            cloudSyncStatusLabel
        }
    }

    private var cloudSyncStatusLabel: some View {
        HStack(spacing: 5) {
            if store.cloudSyncInProgress {
                ProgressView()
                    .controlSize(.mini)
                    .transition(.opacity)
            }
            Image(systemName: cloudSyncStatusSymbol)
                .symbolRenderingMode(.hierarchical)
            Text(cloudSyncStatusText)
        }
        .foregroundStyle(cloudSyncStatusTint)
        .animation(.easeInOut(duration: 0.35), value: store.cloudSyncInProgress)
        .animation(.easeInOut(duration: 0.35), value: store.cloudSyncErrorMessage == nil)
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        #if os(iOS)
        HStack(spacing: 8) {
            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        settings.appearanceMode = mode
                    } label: {
                        if settings.appearanceMode == mode {
                            Label(settings.appearanceDisplayName(mode), systemImage: "checkmark")
                        } else {
                            Text(settings.appearanceDisplayName(mode))
                        }
                    }
                }

                Divider()

                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        settings.appLanguage = lang
                    } label: {
                        if settings.appLanguage == lang {
                            Label(lang.displayName, systemImage: "checkmark")
                        } else {
                            Text(lang.displayName)
                        }
                    }
                }

                Divider()

                Button {
                    settings.iCloudSyncPreference.toggle()
                    applyICloudSyncPreferenceChange()
                } label: {
                    Label(
                        settings.iCloudSyncPreference ? l.iCloudOn : l.iCloudOff,
                        systemImage: settings.iCloudSyncPreference ? "icloud.fill" : "icloud.slash"
                    )
                }

                Divider()

                Button {
                    openPastePermissionSettings()
                } label: {
                    Label(l.pastePermissionSettings, systemImage: "hand.raised.fill")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showingClearAllAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .disabled(store.totalItems == 0)
        }
        #else
        HStack(spacing: 8) {
            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        settings.appearanceMode = mode
                    } label: {
                        if settings.appearanceMode == mode {
                            Label(settings.appearanceDisplayName(mode), systemImage: "checkmark")
                        } else {
                            Text(settings.appearanceDisplayName(mode))
                        }
                    }
                }
            } label: {
                Image(systemName: appearanceIcon)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28, height: 28)
            }
            .macOSBorderlessMenuStyle()
            .platformHelp(l.appearance)

            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        settings.appLanguage = lang
                    } label: {
                        if settings.appLanguage == lang {
                            Label(lang.displayName, systemImage: "checkmark")
                        } else {
                            Text(lang.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "globe")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28, height: 28)
            }
            .macOSBorderlessMenuStyle()
            .platformHelp(l.language)

            Toggle(isOn: $settings.iCloudSyncPreference) {
                Image(systemName: settings.iCloudSyncPreference ? "icloud.fill" : "icloud.slash")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .platformHelp(l.iCloudSync)
            .onChange(of: settings.iCloudSyncPreference) { _ in
                applyICloudSyncPreferenceChange()
            }

            #if os(macOS)
            Divider()
                .frame(height: 18)

            // 快捷键设置
            Button {
                showingHotkeySettings.toggle()
            } label: {
                Image(systemName: "keyboard")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .platformHelp(l.hotkeySettings)
            .popover(isPresented: $showingHotkeySettings, arrowEdge: .bottom) {
                HotkeySettingsView()
                    .environmentObject(settings)
            }

            Toggle(isOn: $settings.autoPasteOnDoubleClick) {
                Label(l.autoPasteOnDoubleClick, systemImage: "command")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .platformHelp(l.autoPasteOnDoubleClickHint)
            .onChange(of: settings.autoPasteOnDoubleClick) { newValue in
                if newValue {
                    ensureAccessibilityPermission(showFallbackAlert: false)
                }
            }
            #endif

            Button(role: .destructive) {
                showingClearAllAlert = true
            } label: {
                Label(l.clearAll, systemImage: "trash")
            }
            .disabled(store.totalItems == 0)
        }
        #endif
    }

    // MARK: - Filter

    @ViewBuilder
    private var filterBar: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ClipboardFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            if selectedFilter == filter {
                                Label(filter.localizedTitle(l), systemImage: "checkmark")
                            } else {
                                Text(filter.localizedTitle(l))
                            }
                        }
                    }
                } label: {
                    Label(
                        selectedFilter.localizedTitle(l),
                        systemImage: selectedFilterMenuSymbol
                    )
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(minHeight: 34)
                }
                .buttonStyle(.bordered)

                Menu {
                    ForEach(TimeFilter.allCases) { tf in
                        Button {
                            selectedTimeFilter = tf
                        } label: {
                            if selectedTimeFilter == tf {
                                Label(tf.localizedTitle(l), systemImage: "checkmark")
                            } else {
                                Text(tf.localizedTitle(l))
                            }
                        }
                    }
                } label: {
                    Label(selectedTimeFilter.localizedTitle(l), systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(minHeight: 34)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                if !searchText.isEmpty {
                    Text(searchText)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.quaternary.opacity(0.6))
                        )
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isSearchExpanded.toggle()
                        if isSearchExpanded {
                            isSearchFocused = true
                        } else if searchText.isEmpty {
                            isSearchFocused = false
                        }
                    }
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSearchExpanded ? .secondary : .primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            if isSearchExpanded || !searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(l.searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #else
        HStack(spacing: 12) {
            Spacer()
            Picker(selection: $selectedFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.localizedTitle(l)).tag(filter)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            Spacer()

            // 时间筛选和搜索
            HStack(spacing: 8) {
                Menu {
                    ForEach(TimeFilter.allCases) { tf in
                        Button {
                            selectedTimeFilter = tf
                        } label: {
                            if selectedTimeFilter == tf {
                                Label(tf.localizedTitle(l), systemImage: "checkmark")
                            } else {
                                Text(tf.localizedTitle(l))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        if selectedTimeFilter != .all {
                            Text(selectedTimeFilter.localizedTitle(l))
                                .font(.caption)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedTimeFilter != .all ? .primary : .secondary)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .macOSBorderlessMenuStyle()

                if isSearchExpanded {
                    TextField(l.searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isSearchFocused)
                        .frame(width: 180)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .platformOnExitCommand {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isSearchExpanded = false
                                searchText = ""
                                isSearchFocused = false
                            }
                        }
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSearchExpanded.toggle()
                        if isSearchExpanded {
                            isSearchFocused = true
                        } else {
                            searchText = ""
                            isSearchFocused = false
                        }
                    }
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSearchExpanded ? .secondary : .primary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .platformHelp(l.search)
            }
        }
        #endif
    }

    private var selectedFilterMenuSymbol: String {
        switch selectedFilter {
        case .all:
            return "tray.full"
        case .favorites:
            return "star.fill"
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }

    // MARK: - Card Area

    private var gridColumns: [GridItem] {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12)]
        #else
        return [GridItem(.adaptive(minimum: 260, maximum: 280), spacing: 16)]
        #endif
    }

    private var cardArea: some View {
        Group {
            if store.cards.isEmpty {
                if !searchText.isEmpty {
                    noSearchResultsState
                } else {
                    emptyState
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(store.cards) { card in
                            ClipboardCardView(
                                card: card,
                                onCopy: { store.copy(card) },
                                onDelete: { store.delete(card) },
                                onToggleFavorite: { store.toggleFavorite(card) },
                                onRequestAccessibility: { ensureAccessibilityPermission(showFallbackAlert: true) },
                                onOpenDetail: { selectedCardForDetail = card }
                            )
                            .environmentObject(store)
                            .environmentObject(settings)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        #if os(iOS)
        .padding(.bottom, 6)
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.linearGradient(
                    colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(l.emptyStateTitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(l.emptyStateSubtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.2))
        }
    }

    private var noSearchResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(l.noSearchResults)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(l.noSearchResultsHint)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.2))
        }
    }

    // MARK: - 权限提示

    private func ensureAccessibilityPermission(showFallbackAlert: Bool = false) {
        #if os(macOS)
        guard !AutoPasteManager.shared.isAccessibilityGranted else { return }
        // 调用系统 API 弹出权限请求对话框，系统会自动将 App 添加到辅助功能列表
        // 并显示带有"打开系统设置"按钮的系统对话框
        AutoPasteManager.shared.requestAccessibilityIfNeeded()
        guard showFallbackAlert else { return }
        // 延迟检查：给系统对话框足够时间显示和用户操作
        // 如果用户关闭了系统对话框但仍未授权，再显示自定义提示作为备用
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
            if !AutoPasteManager.shared.isAccessibilityGranted {
                showingAccessibilityAlert = true
            }
        }
        #endif
    }

    #if os(iOS)
    private func openPastePermissionSettings() {
        guard
            let settingsURL = URL(string: UIApplication.openSettingsURLString),
            UIApplication.shared.canOpenURL(settingsURL)
        else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }
    #endif

    private func applyICloudSyncPreferenceChange() {
        runtime.applyICloudPreferenceChange()
    }
}

// MARK: - 声音管理器

enum SoundManager {
    #if os(macOS)
    private static let pasteSoundName = "Copy"
    private static let pasteSoundExtension = "aiff"

    private static var copySound: NSSound? = {
        if
            let url = Bundle.main.url(forResource: pasteSoundName, withExtension: pasteSoundExtension)
            ?? Bundle.main.url(forResource: pasteSoundName, withExtension: pasteSoundExtension, subdirectory: "Resources")
        {
            return NSSound(contentsOf: url, byReference: true)
        }

        let pasteAppURL = URL(fileURLWithPath: "/Applications/Paste.app/Contents/Resources/Copy.aiff")
        return NSSound(contentsOf: pasteAppURL, byReference: true)
    }()

    static func playCopySound() {
        guard let sound = copySound else { return }
        if sound.isPlaying {
            sound.stop()
        }
        sound.play()
    }
    #else
    static func playCopySound() {
        // iOS 端查询/阅读场景：提供轻量触觉反馈
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    #endif
}

// MARK: - Card View

private struct ClipboardCardView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @State private var isHovered = false
    #if os(iOS)
    @State private var resolvedAppIcon: PlatformImage?
    #endif

    let card: ClipboardCard
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onRequestAccessibility: () -> Void
    let onOpenDetail: () -> Void

    private var l: L { settings.l }
    private var thumbnailHeight: CGFloat {
        #if os(iOS)
        return 116
        #else
        return 132
        #endif
    }

    private var defaultTextLineLimit: Int {
        #if os(iOS)
        return 5
        #else
        return 6
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：左边图标+程序名，右边删除按钮
            HStack {
                sourceIcon
                Text(card.sourceAppName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    if card.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                    }
                    #if os(iOS)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    #else
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .opacity(isHovered ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .platformHelp(l.delete)
                    #endif
                }
            }

            content

            Spacer(minLength: 4)

            // 底部：左边字符数/尺寸，右边时间
            HStack {
                Text(contentMetaText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(relativeTimeString(for: card.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 260, height: 220, alignment: .topLeading)
        #else
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        #endif
        .contentShape(Rectangle())
        #if os(macOS)
        .onTapGesture(count: 2) {
            onCopy()
            SoundManager.playCopySound()
            if settings.autoPasteOnDoubleClick {
                if !AutoPasteManager.shared.performAutoPaste() {
                    onRequestAccessibility()
                }
            }
        }
        #else
        .onTapGesture {
            onOpenDetail()
        }
        #endif
        .contextMenu {
            Button {
                onCopy()
                SoundManager.playCopySound()
            } label: {
                Label(l.copy, systemImage: "doc.on.doc")
            }

            Button(action: onToggleFavorite) {
                Label(
                    card.isFavorite ? l.unfavorite : l.favorite,
                    systemImage: card.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label(l.delete, systemImage: "trash")
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background)
                .shadow(
                    color: .black.opacity(isHovered ? 0.15 : 0.08),
                    radius: isHovered ? 12 : 6,
                    y: isHovered ? 4 : 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHovered
                        ? Color.accentColor.opacity(0.4)
                        : Color.primary.opacity(0.06),
                    lineWidth: isHovered ? 1.5 : 1
                )
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .platformOnHover { hovering in
            isHovered = hovering
        }
        .platformHelp(
            {
                #if os(iOS)
                return l.tapToViewDetail
                #else
                return settings.autoPasteOnDoubleClick ? l.doubleClickToPaste : l.clickToCopy
                #endif
            }()
        )
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            smartContentView
        case .url:
            Text(card.previewText)
                .font(.body)
                .lineLimit(3)
                .foregroundStyle(.blue)
        case .image:
            CachedThumbnailView(key: card.thumbnailKey)
                .environmentObject(store)
                .frame(maxWidth: .infinity, minHeight: thumbnailHeight, maxHeight: thumbnailHeight)
                .clipped()
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// 根据智能识别类型渲染不同的文本内容预览
    @ViewBuilder
    private var smartContentView: some View {
        switch card.smartContentType {
        case .color(let r, let g, let b, let a):
            colorPreview(r: r, g: g, b: b, a: a)
        case .phoneNumber:
            iconLabelPreview(
                icon: "phone.fill",
                iconColor: .green,
                text: card.previewText
            )
        case .email:
            iconLabelPreview(
                icon: "envelope.fill",
                iconColor: .blue,
                text: card.previewText
            )
        case .none:
            Text(card.previewText)
                .font(.body)
                .lineLimit(defaultTextLineLimit)
        }
    }

    /// 颜色预览：大色块 + 底部颜色代码
    private func colorPreview(r: Double, g: Double, b: Double, a: Double) -> some View {
        let color = Color(red: r, green: g, blue: b, opacity: a)
        // 计算亮度，决定文字颜色（深色背景用白字，浅色背景用黑字）
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        let textColor: Color = luminance > 0.5 ? .black : .white

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color)
            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 132)
            .overlay(alignment: .bottom) {
                // 棋盘格背景（用于透明色预览）
                if a < 1 {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            .linearGradient(
                                colors: [.white.opacity(0.3), .clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                }
            }
            .overlay(alignment: .center) {
                VStack(spacing: 6) {
                    // 显示颜色代码
                    Text(card.previewText)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(textColor.opacity(0.9))

                    // 显示 RGB 值
                    Text("R:\(Int(r * 255)) G:\(Int(g * 255)) B:\(Int(b * 255))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.6))
                }
                .padding(.horizontal, 8)
            }
    }

    /// 带图标的内容预览（电话、邮箱等）
    private func iconLabelPreview(icon: String, iconColor: Color, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(iconColor.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)

            Text(text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: - Helpers

    /// 内容元信息：字符数或图片尺寸或智能类型
    private var contentMetaText: String {
        switch card.kind {
        case .text, .url:
            let smartLabel: String? = {
                switch card.smartContentType {
                case .color: return l.smartColor
                case .phoneNumber: return l.smartPhone
                case .email: return l.smartEmail
                case .none: return nil
                }
            }()
            if let label = smartLabel {
                return "\(label) · \(l.characterCount(card.characterCount))"
            }
            return l.characterCount(card.characterCount)
        case .image:
            if let w = card.imageWidth, let h = card.imageHeight {
                return "\(w) × \(h)"
            }
            return l.kindImage
        }
    }

    private func appIcon(for bundleID: String) -> PlatformImage? {
        #if os(macOS)
        return AppIconProvider.shared.cachedIcon(for: bundleID)
        #else
        return resolvedAppIcon ?? AppIconProvider.shared.cachedIcon(for: bundleID)
        #endif
    }

    @ViewBuilder
    private var sourceIcon: some View {
        Group {
            if let icon = appIcon(for: card.sourceBundleID) {
                Image(platformImage: icon)
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sourceBadgeColor.opacity(0.16))
                    .frame(width: 28, height: 28)
                    .overlay {
                        if let symbol = sourceFallbackSymbol {
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(sourceBadgeColor)
                        } else {
                            Text(sourceInitial)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(sourceBadgeColor)
                        }
                    }
            }
        }
        #if os(iOS)
        .task(id: card.sourceBundleID) {
            guard AppIconProvider.shared.cachedIcon(for: card.sourceBundleID) == nil else { return }
            resolvedAppIcon = await AppIconProvider.shared.fetchIconIfNeeded(for: card.sourceBundleID)
        }
        #endif
    }

    private var sourceInitial: String {
        let raw = card.sourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = raw.first else { return "?" }
        return String(first).uppercased()
    }

    private var sourceBadgeColor: Color {
        if card.sourceBundleID == "system.pasteboard" {
            return .teal
        }

        switch card.kind {
        case .text:
            return .blue
        case .url:
            return .indigo
        case .image:
            return .orange
        }
    }

    private var sourceFallbackSymbol: String? {
        let lower = card.sourceBundleID.lowercased()
        if lower.contains("pasteboard") || lower.contains("clipboard") {
            return "list.clipboard.fill"
        }
        if lower.contains("safari") {
            return "safari.fill"
        }
        if lower.contains("notes") {
            return "note.text"
        }
        if lower.contains("messages") || lower.contains("imessage") {
            return "message.fill"
        }
        if lower.contains("mail") {
            return "envelope.fill"
        }
        if lower.contains("photos") {
            return "photo.on.rectangle"
        }
        if lower.contains("chrome") {
            return "globe"
        }
        if lower.contains("wechat") {
            return "message.circle.fill"
        }
        return nil
    }

    private func relativeTimeString(for date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return l.timeJustNow
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return l.timeMinutesAgo(minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return l.timeHoursAgo(hours)
        } else {
            let days = Int(interval / 86400)
            if days == 1 {
                return l.timeYesterday
            } else if days < 7 {
                return l.timeDaysAgo(days)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = l.lang == .zh ? "M月d日" : "MMM d"
                return formatter.string(from: date)
            }
        }
    }

}

#if os(iOS)
private struct ClipboardDetailSheet: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingCopiedHint = false
    @State private var isFavorite: Bool
    @State private var showingImageViewer = false
    @State private var viewerImage: PlatformImage?

    let card: ClipboardCard

    init(card: ClipboardCard) {
        self.card = card
        _isFavorite = State(initialValue: card.isFavorite)
    }

    private var l: L { settings.l }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(card.sourceAppName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    detailContent

                    HStack {
                        Text(metaLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(relativeTimeString(for: card.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if showingCopiedHint {
                        Label(l.copiedSuccess, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
                .padding(20)
            }
            .navigationTitle(l.detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l.cancel) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isFavorite.toggle()
                        store.toggleFavorite(card)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                    }

                    Button {
                        copyAndHint()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        store.delete(card)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingImageViewer) {
                if let viewerImage {
                    ZoomableImageViewer(image: viewerImage)
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch card.kind {
        case .text:
            Text(card.previewText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.25))
                )
        case .url:
            VStack(alignment: .leading, spacing: 12) {
                Text(card.previewText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let url = URL(string: card.previewText) {
                    Link(destination: url) {
                        Label(l.openInBrowser, systemImage: "safari")
                            .font(.callout.weight(.medium))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.25))
            )
        case .image:
            if let image = store.fullImage(for: card) ?? store.thumbnail(forKey: card.thumbnailKey) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewerImage = image
                        showingImageViewer = true
                    }
                    .overlay(alignment: .bottom) {
                        Text(l.tapToZoomImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                    }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.25))
                    .frame(height: 220)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private var metaLine: String {
        switch card.kind {
        case .image:
            if let w = card.imageWidth, let h = card.imageHeight {
                return "\(w) × \(h)"
            }
            return l.kindImage
        case .text, .url:
            return l.characterCount(card.characterCount)
        }
    }

    private func copyAndHint() {
        store.copy(card)
        SoundManager.playCopySound()
        withAnimation(.easeInOut(duration: 0.18)) {
            showingCopiedHint = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingCopiedHint = false
            }
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return l.timeJustNow
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return l.timeMinutesAgo(minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return l.timeHoursAgo(hours)
        } else {
            let days = Int(interval / 86400)
            if days == 1 {
                return l.timeYesterday
            } else if days < 7 {
                return l.timeDaysAgo(days)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = l.lang == .zh ? "M月d日" : "MMM d"
                return formatter.string(from: date)
            }
        }
    }
}

private struct ZoomableImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragTranslation: CGSize = .zero

    let image: PlatformImage

    @State private var baseScale: CGFloat = 1
    @State private var pinchScale: CGFloat = 1
    @State private var accumulatedOffset: CGSize = .zero

    private var currentScale: CGFloat {
        min(max(baseScale * pinchScale, 1), 5)
    }

    private var currentOffset: CGSize {
        CGSize(
            width: accumulatedOffset.width + dragTranslation.width,
            height: accumulatedOffset.height + dragTranslation.height
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(currentScale)
                .offset(currentOffset)
                .padding(12)
                .gesture(combinedGesture)
                .onTapGesture(count: 2) {
                    resetTransform()
                }
                .animation(.easeInOut(duration: 0.16), value: baseScale)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }

    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    pinchScale = value
                }
                .onEnded { value in
                    baseScale = min(max(baseScale * value, 1), 5)
                    pinchScale = 1
                    if baseScale <= 1 {
                        accumulatedOffset = .zero
                    }
                },
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = currentScale > 1 ? value.translation : .zero
                }
                .onEnded { value in
                    guard currentScale > 1 else {
                        accumulatedOffset = .zero
                        return
                    }
                    accumulatedOffset.width += value.translation.width
                    accumulatedOffset.height += value.translation.height
                }
        )
    }

    private func resetTransform() {
        baseScale = 1
        pinchScale = 1
        accumulatedOffset = .zero
    }
}
#endif

// MARK: - Thumbnail View

private struct CachedThumbnailView: View {
    @EnvironmentObject private var store: ClipboardStore

    let key: String?
    @State private var image: PlatformImage?
    private let maxZoom: CGFloat = 1.12

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    let containerSize = proxy.size
                    let containerAspect = containerSize.width / max(containerSize.height, 1)
                    let imageSize = image.size
                    let imageAspect = imageSize.width / max(imageSize.height, 1)
                    let ratio = containerAspect / max(imageAspect, 0.0001)
                    let zoomToFill = max(ratio, 1 / ratio)
                    let zoom = min(maxZoom, zoomToFill)

                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .frame(width: containerSize.width, height: containerSize.height)
                        .clipped()
                        .background(Color.secondary.opacity(0.12))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary.opacity(0.3))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            image = store.thumbnail(forKey: key)
        }
        .onChange(of: key) { newKey in
            image = store.thumbnail(forKey: newKey)
        }
    }
}
