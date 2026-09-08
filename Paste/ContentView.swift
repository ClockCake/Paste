import SwiftUI
import Combine
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var runtime: AppRuntime
    @ObservedObject private var autoPaste = AutoPasteManager.shared

    @State private var showingClearAllAlert = false
    @State private var showingCloudErrorAlert = false
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var settingsViewId = UUID()
    @State private var showingDeleteByDateSheet = false
    @State private var showingCustomDateFilter = false
    @State private var showingDeleteBeforeAlert = false
    @State private var deleteBeforeLabel = ""
    @State private var deleteBeforeDate = Date()
    @State private var deleteBeforeCount = 0
    @State private var nowTick = Date()
    /// 当前键盘选中的卡片
    @State private var selectedCardID: UUID?
    /// 网格实际列数，上下方向键要靠它换行
    @State private var gridColumnCount = 1
    @FocusState private var focusedArea: FocusArea?

    /// 键盘焦点区域。搜索框获得焦点时，网格不应再响应方向键和删除键
    private enum FocusArea: Hashable {
        case grid
        case search
    }

    private let cardMinWidth: CGFloat = 260
    private let gridSpacing: CGFloat = 16
    private let contentPadding: CGFloat = 20

    private var l: L { settings.l }

    private var selectedCard: ClipboardCard? {
        guard let selectedCardID else { return nil }
        return store.cards.first { $0.id == selectedCardID }
    }

    private var isAutoPasteEnabled: Bool {
        settings.autoPasteOnDoubleClick && autoPaste.isAccessibilityGranted
    }

    // MARK: - iCloud 状态

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
        return .secondary
    }
    private var cloudLastSyncedText: String? {
        guard store.cloudSyncEnabled else { return nil }
        guard let lastSyncDate = store.lastSuccessfulCloudSyncDate else {
            return l.iCloudNotSyncedYet
        }
        return l.iCloudLastSynced(l.relativeTimeSince(lastSyncDate, now: nowTick))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            cardArea
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 520)
        .background(keyboardCommands)
        .navigationTitle(l.appTitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                filterPicker
            }
            ToolbarItemGroup(placement: .primaryAction) {
                timeFilterMenu
                searchField
                deleteMenu
                settingsButton
            }
        }
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
        .alert(l.deleteManage, isPresented: $showingDeleteBeforeAlert) {
            Button(l.cancel, role: .cancel) {}
            Button(l.delete, role: .destructive) {
                store.deleteRecordsBefore(date: deleteBeforeDate)
            }
        } message: {
            Text(l.deleteBeforeConfirm(deleteBeforeLabel, deleteBeforeCount))
        }
        .onChange(of: settings.iCloudSyncPreference) { _ in
            runtime.applyICloudPreferenceChange()
        }
        .task {
            selectedFilter = store.currentFilter
            selectedTimeFilter = store.currentTimeFilter
            NSApp.appearance = settings.appearanceMode.nsAppearance
            autoPaste.refreshAccessibilityState()
            focusedArea = .grid
            syncSelection()
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
        .onChange(of: ObjectIdentifier(store)) { _ in
            DispatchQueue.main.async {
                store.updateFilter(selectedFilter)
                store.updateSearch(searchText)
                store.updateTimeFilter(selectedTimeFilter)
            }
        }
        .onChange(of: store.cards.count) { _ in
            syncSelection()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            nowTick = date
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            autoPaste.refreshAccessibilityState()
        }
    }

    // MARK: - Toolbar

    private var filterPicker: some View {
        Picker(selection: $selectedFilter) {
            ForEach(ClipboardFilter.allCases) { filter in
                Text(filter.localizedTitle(l)).tag(filter)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .frame(width: 320)
    }

    private var timeFilterMenu: some View {
        Menu {
            ForEach(TimeFilter.presetCases) { tf in
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

            Divider()

            Button {
                showingCustomDateFilter = true
            } label: {
                if selectedTimeFilter == .customRange {
                    Label(l.timeFilterCustom, systemImage: "checkmark")
                } else {
                    Text(l.timeFilterCustom)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                if selectedTimeFilter == .customRange,
                   let from = store.currentCustomDateFrom,
                   let to = store.currentCustomDateTo {
                    Text(l.customDateRangeLabel(from: from, to: to))
                        .font(.caption)
                } else if selectedTimeFilter != .all {
                    Text(selectedTimeFilter.localizedTitle(l))
                        .font(.caption)
                }
            }
            .foregroundStyle(selectedTimeFilter != .all ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .macOSBorderlessMenuStyle()
        .platformHelp(l.timeFilterLabel)
        .popover(isPresented: $showingCustomDateFilter, arrowEdge: .bottom) {
            DatePickerSheet(
                isPresented: $showingCustomDateFilter,
                mode: .filter,
                onApplyFilter: { from, to in
                    store.updateCustomDateRange(from: from, to: to)
                    selectedTimeFilter = .customRange
                }
            )
            .environmentObject(store)
            .environmentObject(settings)
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(l.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 130)
                .focused($focusedArea, equals: .search)
                .platformOnExitCommand {
                    clearSearch()
                }
            if !searchText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
        .platformHelp(l.search)
    }

    private var deleteMenu: some View {
        Menu {
            Button {
                prepareDeleteBefore(label: l.deleteBeforeWeek, days: 7)
            } label: {
                Label(l.deleteBeforeWeek, systemImage: "clock.badge.xmark")
            }

            Button {
                prepareDeleteBefore(label: l.deleteBeforeHalfMonth, days: 15)
            } label: {
                Label(l.deleteBeforeHalfMonth, systemImage: "clock.badge.xmark")
            }

            Button {
                prepareDeleteBefore(label: l.deleteBeforeMonth, days: 30)
            } label: {
                Label(l.deleteBeforeMonth, systemImage: "clock.badge.xmark")
            }

            Button {
                prepareDeleteBefore(label: l.deleteBefore3Months, days: 90)
            } label: {
                Label(l.deleteBefore3Months, systemImage: "clock.badge.xmark")
            }

            Divider()

            Button {
                showingDeleteByDateSheet = true
            } label: {
                Label(l.deleteByDate, systemImage: "calendar.badge.minus")
            }

            Divider()

            Button(role: .destructive) {
                showingClearAllAlert = true
            } label: {
                Label(l.clearAll, systemImage: "trash")
            }
        } label: {
            Image(systemName: "trash")
                .symbolRenderingMode(.hierarchical)
        }
        .macOSBorderlessMenuStyle()
        .platformHelp(l.deleteManage)
        .popover(isPresented: $showingDeleteByDateSheet, arrowEdge: .bottom) {
            DatePickerSheet(
                isPresented: $showingDeleteByDateSheet,
                mode: .delete
            )
            .environmentObject(store)
            .environmentObject(settings)
        }
        .disabled(store.totalItems == 0)
    }

    private var settingsButton: some View {
        Button {
            showingSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
                .symbolRenderingMode(.hierarchical)
        }
        .platformHelp(l.settings)
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsView(isPresented: $showingSettings)
                .environmentObject(settings)
                .id(settingsViewId)
        }
        .onChange(of: showingSettings) { newValue in
            if newValue {
                settingsViewId = UUID()
            }
        }
    }

    // MARK: - 底部状态栏

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(l.itemCount(store.totalItems))
            Text(store.storageText)
            cloudSyncStatusInline
            if let syncedText = cloudLastSyncedText {
                Text(syncedText)
            }
            Spacer(minLength: 12)
            Text(l.keyboardHint)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, contentPadding)
        .padding(.vertical, 6)
        .background(.bar)
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

    // MARK: - 卡片区

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth), spacing: gridSpacing)]
    }

    /// 由可用宽度推算 LazyVGrid 的实际列数，与 .adaptive 的排布规则保持一致
    private func columnCount(forWidth width: CGFloat) -> Int {
        let usable = width - contentPadding * 2
        guard usable > 0 else { return 1 }
        return max(1, Int((usable + gridSpacing) / (cardMinWidth + gridSpacing)))
    }

    private var cardArea: some View {
        GeometryReader { proxy in
            let columns = columnCount(forWidth: proxy.size.width)
            Group {
                if store.cards.isEmpty {
                    if searchText.isEmpty {
                        emptyPlaceholder(
                            symbol: "clipboard",
                            title: l.emptyStateTitle,
                            subtitle: l.emptyStateSubtitle,
                            tinted: true
                        )
                    } else {
                        emptyPlaceholder(
                            symbol: "magnifyingglass",
                            title: l.noSearchResults,
                            subtitle: l.noSearchResultsHint,
                            tinted: false
                        )
                    }
                } else {
                    cardGrid
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { gridColumnCount = columns }
            .onChange(of: columns) { newValue in gridColumnCount = newValue }
        }
    }

    private var cardGrid: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                    ForEach(store.cards) { card in
                        ClipboardCardView(
                            card: card,
                            now: nowTick,
                            isSelected: card.id == selectedCardID,
                            isAutoPasteEnabled: isAutoPasteEnabled,
                            onSelect: { selectedCardID = card.id; focusedArea = .grid },
                            onActivate: { activate(card) },
                            onCopy: { copyOnly(card) },
                            onDelete: { delete(card) },
                            onToggleFavorite: { store.toggleFavorite(card) }
                        )
                        .environmentObject(store)
                        .environmentObject(settings)
                    }
                }
                .padding(contentPadding)
                .animation(.easeInOut(duration: 0.18), value: store.cards.count)
            }
            .focusable()
            .focused($focusedArea, equals: .grid)
            .onMoveCommand { direction in
                moveSelection(direction)
            }
            .onDeleteCommand {
                if let card = selectedCard {
                    delete(card)
                }
            }
            .platformOnExitCommand {
                closeWindow()
            }
            .onChange(of: selectedCardID) { newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollProxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func emptyPlaceholder(
        symbol: String,
        title: String,
        subtitle: String,
        tinted: Bool
    ) -> some View {
        VStack(spacing: 12) {
            Group {
                if tinted {
                    Image(systemName: symbol)
                        .foregroundStyle(.linearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 40, weight: .light))

            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 键盘操作

    /// 承载全窗口快捷键的隐藏按钮组。零尺寸且透明，只为注册快捷键
    private var keyboardCommands: some View {
        Group {
            // ⌘1–9：直接对第 N 个条目执行复制（配合自动粘贴设置则连带粘贴）
            ForEach(1...9, id: \.self) { index in
                Button("") {
                    activateCard(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }

            // ↩：对选中条目执行复制/粘贴
            Button("") {
                guard focusedArea != .search, let card = selectedCard else { return }
                activate(card)
            }
            .keyboardShortcut(.return, modifiers: [])

            // ⌘C：仅复制，不触发自动粘贴
            Button("") {
                guard focusedArea != .search, let card = selectedCard else { return }
                copyOnly(card)
            }
            .keyboardShortcut("c", modifiers: .command)

            // ⌘D：收藏 / 取消收藏
            Button("") {
                guard focusedArea != .search, let card = selectedCard else { return }
                store.toggleFavorite(card)
            }
            .keyboardShortcut("d", modifiers: .command)

            // ⌘F：聚焦搜索框
            Button("") {
                focusedArea = .search
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let cards = store.cards
        guard !cards.isEmpty else { return }

        guard
            let current = selectedCardID,
            let index = cards.firstIndex(where: { $0.id == current })
        else {
            selectedCardID = cards.first?.id
            return
        }

        let columns = max(gridColumnCount, 1)
        let target: Int
        switch direction {
        case .left:  target = index - 1
        case .right: target = index + 1
        case .up:    target = index - columns
        case .down:  target = index + columns
        @unknown default: return
        }

        guard cards.indices.contains(target) else { return }
        selectedCardID = cards[target].id
    }

    /// 选中列表中第 index 个条目并执行主操作，供 ⌘1–9 使用
    private func activateCard(at index: Int) {
        guard store.cards.indices.contains(index) else { return }
        let card = store.cards[index]
        selectedCardID = card.id
        activate(card)
    }

    /// 卡片主操作：URL 可选直接打开浏览器，否则复制并按设置自动粘贴
    private func activate(_ card: ClipboardCard) {
        if card.kind == .url && settings.openURLOnDoubleClick {
            if let url = URL(string: card.previewText) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        copyOnly(card)

        guard settings.autoPasteOnDoubleClick else { return }
        if autoPaste.isAccessibilityGranted {
            if !autoPaste.performAutoPaste() {
                autoPaste.requestAccessibilityIfNeeded()
            }
        } else {
            autoPaste.requestAccessibilityIfNeeded()
        }
    }

    private func copyOnly(_ card: ClipboardCard) {
        store.copy(card)
        SoundManager.playCopySound()
    }

    /// 删除卡片，并把选中态挪到相邻条目上
    private func delete(_ card: ClipboardCard) {
        if card.id == selectedCardID {
            let cards = store.cards
            if let index = cards.firstIndex(where: { $0.id == card.id }) {
                let neighbour = index + 1 < cards.count ? cards[index + 1] : (index > 0 ? cards[index - 1] : nil)
                selectedCardID = neighbour?.id
            }
        }
        store.delete(card)
    }

    /// 同步选中态：默认选中首条，选中项被删掉后落回首条
    private func syncSelection() {
        guard let selectedCardID else {
            self.selectedCardID = store.cards.first?.id
            return
        }
        if !store.cards.contains(where: { $0.id == selectedCardID }) {
            self.selectedCardID = store.cards.first?.id
        }
    }

    private func clearSearch() {
        searchText = ""
        focusedArea = .grid
    }

    private func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    /// 快捷删除：准备删除指定天数之前的记录
    private func prepareDeleteBefore(label: String, days: Int) {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        deleteBeforeLabel = label
        deleteBeforeDate = date
        deleteBeforeCount = store.countRecordsBefore(date: date)
        showingDeleteBeforeAlert = true
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
    /// 由外部统一驱动的“当前时间”，保证相对时间文案会随时间刷新
    let now: Date
    let isSelected: Bool
    let isAutoPasteEnabled: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    private var l: L { settings.l }
    private let thumbnailHeight: CGFloat = 132
    private let defaultTextLineLimit = 6

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if isHovered { return .accentColor.opacity(0.4) }
        return .primary.opacity(0.06)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
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
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .opacity(isHovered ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .platformHelp(l.delete)
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
                Text(l.relativeTimeSince(card.createdAt, now: now, fallbackToDateAfterDays: 7))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 176, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        // 双击必须先声明，否则会被单击手势抢先消费
        .onTapGesture(count: 2, perform: onActivate)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(action: onCopy) {
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
                    color: .black.opacity(isHovered || isSelected ? 0.13 : 0.08),
                    radius: isHovered || isSelected ? 10 : 6,
                    y: 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .platformOnHover { hovering in
            isHovered = hovering
        }
        .platformHelp(isAutoPasteEnabled ? l.doubleClickToPaste : l.clickToCopy)
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
                // 半透明色叠一层渐变，便于看出透明度
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
                    Text(card.previewText)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(textColor.opacity(0.9))

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

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = AppIconProvider.shared.cachedIcon(for: card.sourceBundleID) {
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
}

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
