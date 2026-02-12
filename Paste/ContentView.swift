import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @State private var showingClearAllAlert = false
    @State private var showingRestartAlert = false
    @State private var showingCloudErrorAlert = false
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @State private var showingHotkeySettings = false
    @State private var showingAccessibilityAlert = false
    @FocusState private var isSearchFocused: Bool

    private var l: L { settings.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            filterBar
            cardArea
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 520)
        .alert(l.clearAllConfirmTitle, isPresented: $showingClearAllAlert) {
            Button(l.cancel, role: .cancel) {}
            Button(l.clear, role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text(l.clearAllConfirmMessage)
        }
        .alert(l.iCloudSync, isPresented: $showingRestartAlert) {
            Button("OK") {}
        } message: {
            Text(l.iCloudRestartHint)
        }
        .alert(l.iCloudErrorTitle, isPresented: $showingCloudErrorAlert) {
            Button("OK") {}
        } message: {
            Text(store.cloudSyncErrorMessage ?? l.iCloudErrorUnknown)
        }
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
        .task {
            NSApp.appearance = settings.appearanceMode.nsAppearance
            selectedFilter = store.currentFilter
            selectedTimeFilter = store.currentTimeFilter
            if settings.autoPasteOnDoubleClick {
                ensureAccessibilityPermission()
            }
        }
        .onChange(of: settings.appearanceMode) { newValue in
            NSApp.appearance = newValue.nsAppearance
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
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.appTitle)
                    .font(.largeTitle.weight(.bold))
                Text(l.appSubtitle)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text(l.itemCount(store.totalItems))
                    Text(store.storageText)
                    Text(store.cloudSyncEnabled ? l.iCloudOn : l.iCloudOff)
                    if store.cloudSyncErrorMessage != nil {
                        Button {
                            showingCloudErrorAlert = true
                        } label: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help(l.iCloudErrorHint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            toolbarButtons
        }
    }

    // MARK: - Toolbar

    private var appearanceIcon: String {
        switch settings.appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private var toolbarButtons: some View {
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
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(l.appearance)

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
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(l.language)

            Toggle(isOn: $settings.iCloudSyncPreference) {
                Image(systemName: settings.iCloudSyncPreference ? "icloud.fill" : "icloud.slash")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(l.iCloudSync)
            .onChange(of: settings.iCloudSyncPreference) { _ in
                showingRestartAlert = true
            }

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
            .help(l.hotkeySettings)
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
            .help(l.autoPasteOnDoubleClickHint)
            .onChange(of: settings.autoPasteOnDoubleClick) { newValue in
                if newValue {
                    ensureAccessibilityPermission()
                }
            }

            Button(role: .destructive) {
                showingClearAllAlert = true
            } label: {
                Label(l.clearAll, systemImage: "trash")
            }
            .disabled(store.totalItems == 0)
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
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
                .menuStyle(.borderlessButton)
                .fixedSize()

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
                        .onExitCommand {
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
                .help(l.search)
            }
        }
    }

    // MARK: - Card Area

    private let gridColumns = [
        GridItem(.adaptive(minimum: 260, maximum: 280), spacing: 16)
    ]

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
                                onRequestAccessibility: { ensureAccessibilityPermission() }
                            )
                            .environmentObject(store)
                            .environmentObject(settings)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
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

    private func ensureAccessibilityPermission() {
        guard !AutoPasteManager.shared.isAccessibilityGranted else { return }
        AutoPasteManager.shared.requestAccessibilityIfNeeded()
        showingAccessibilityAlert = true
    }
}

// MARK: - 声音管理器

enum SoundManager {
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
}

// MARK: - Card View

private struct ClipboardCardView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @State private var isHovered = false

    let card: ClipboardCard
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onRequestAccessibility: () -> Void

    private var l: L { settings.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：左边图标+程序名，右边删除按钮
            HStack {
                if let icon = appIcon(for: card.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: card.kind.symbolName)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
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
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .opacity(isHovered ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .help(l.delete)
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
        .frame(width: 260, height: 220, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onCopy()
            SoundManager.playCopySound()
            if settings.autoPasteOnDoubleClick {
                if !AutoPasteManager.shared.performAutoPaste() {
                    onRequestAccessibility()
                }
            }
        }
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
        .onHover { hovering in
            isHovered = hovering
        }
        .help(settings.autoPasteOnDoubleClick ? l.doubleClickToPaste : l.clickToCopy)
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            smartContentView
        case .url:
            Text(card.previewText)
                .font(.body)
                .lineLimit(4)
                .foregroundStyle(.blue)
        case .image:
            CachedThumbnailView(key: card.thumbnailKey)
                .environmentObject(store)
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 132)
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
                .lineLimit(6)
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

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
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

// MARK: - Thumbnail View

private struct CachedThumbnailView: View {
    @EnvironmentObject private var store: ClipboardStore

    let key: String?
    @State private var image: NSImage?
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

                    Image(nsImage: image)
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
