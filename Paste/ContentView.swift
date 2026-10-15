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

    private let cardMinWidth: CGFloat = 250
    private let gridSpacing: CGFloat = 16
    private let contentPadding: CGFloat = 28

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
        return PasteTheme.accent
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
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(PasteTheme.border)
                .frame(width: 1)
            VStack(spacing: 0) {
                workspaceHeader
                cardArea
                statusBar
            }
            .background(PasteTheme.canvas)
        }
        .frame(minWidth: 900, minHeight: 560)
        .tint(PasteTheme.accent)
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .background(keyboardCommands)
        .navigationTitle(l.appTitle)
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
        .onChange(of: store.cards.map(\.id)) { _ in
            syncSelection()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            nowTick = date
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            autoPaste.refreshAccessibilityState()
        }
    }

    // MARK: - 侧边栏与工作区标题

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(PasteTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(PasteTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.appTitle)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .tracking(-0.6)
                    Text(l.clipboardHistory)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 34)

            sidebarSectionTitle(l.library)
            VStack(spacing: 5) {
                sidebarItem(.all, title: l.allClips, symbol: "square.grid.2x2")
                sidebarItem(.favorites, title: l.favoriteClips, symbol: "star")
            }
            .padding(.horizontal, 12)

            sidebarSectionTitle(l.contentTypes)
                .padding(.top, 27)
            VStack(spacing: 5) {
                sidebarItem(.text, title: l.filterText, symbol: "text.alignleft")
                sidebarItem(.url, title: l.filterURL, symbol: "link")
                sidebarItem(.image, title: l.filterImage, symbol: "photo")
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 10) {
                cloudSyncStatusInline
                    .font(.system(size: 11, weight: .medium))
                if let syncedText = cloudLastSyncedText {
                    Text(syncedText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Text(l.itemCount(store.totalItems))
                    Text("·")
                    Text(store.storageText)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PasteTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .padding(12)

            settingsButton
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(PasteTheme.sidebar)
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
    }

    private func sidebarItem(_ filter: ClipboardFilter, title: String, symbol: String) -> some View {
        let isActive = selectedFilter == filter
        return Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                Spacer(minLength: 0)
                if filter == .all {
                    Text("\(store.totalItems)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PasteTheme.surface.opacity(0.65), in: Capsule())
                }
            }
            .foregroundStyle(isActive ? PasteTheme.accent : Color.primary.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background(isActive ? PasteTheme.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var workspaceTitle: String {
        switch selectedFilter {
        case .all: return l.allClips
        case .favorites: return l.favoriteClips
        default: return selectedFilter.localizedTitle(l)
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(workspaceTitle)
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.6)
                    Text(selectedFilter == .favorites ? l.favoritesSubtitle : l.workspaceSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                deleteMenu
            }
            HStack(spacing: 12) {
                searchField
                timeFilterMenu
            }
            HStack(spacing: 8) {
                Text(l.itemCount(store.cards.count))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                Text(l.newestFirst)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, contentPadding)
        .padding(.top, 26)
        .padding(.bottom, 4)
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
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                if selectedTimeFilter == .customRange,
                   let from = store.currentCustomDateFrom,
                   let to = store.currentCustomDateTo {
                    Text(l.customDateRangeLabel(from: from, to: to))
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Text(selectedTimeFilter.localizedTitle(l))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(selectedTimeFilter != .all ? PasteTheme.accent : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(PasteTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PasteTheme.border, lineWidth: 1))
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
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(l.searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel(l.search)
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
                .accessibilityLabel(l.clear)
            } else {
                Text("⌘ F")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(PasteTheme.inset, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(PasteTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            focusedArea == .search ? PasteTheme.accent.opacity(0.65) : PasteTheme.border,
            lineWidth: 1
        ))
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
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 30)
                .background(PasteTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        }
        .macOSBorderlessMenuStyle()
        .platformHelp(l.deleteManage)
        .accessibilityLabel(l.deleteManage)
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
            HStack(spacing: 11) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(l.settings)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .platformHelp(l.settings)
        .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
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
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 12))
            Text(l.keyboardHint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, contentPadding)
        .padding(.vertical, 12)
        .background(PasteTheme.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(PasteTheme.border.opacity(0.7)).frame(height: 1)
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
                    if !searchText.isEmpty {
                        emptyPlaceholder(
                            symbol: "magnifyingglass",
                            title: l.noSearchResults,
                            subtitle: l.noSearchResultsHint,
                            tinted: false
                        )
                    } else if selectedFilter != .all || selectedTimeFilter != .all {
                        emptyPlaceholder(
                            symbol: selectedFilter == .favorites ? "star" : "line.3.horizontal.decrease.circle",
                            title: l.noFilteredResults,
                            subtitle: l.noFilteredResultsHint,
                            tinted: true
                        )
                    } else {
                        emptyPlaceholder(
                            symbol: "clipboard",
                            title: l.emptyStateTitle,
                            subtitle: l.emptyStateSubtitle,
                            tinted: true
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
                    ForEach(Array(store.cards.enumerated()), id: \.element.id) { index, card in
                        ClipboardCardView(
                            card: card,
                            now: nowTick,
                            shortcutNumber: index < 9 ? index + 1 : nil,
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
                        .id(card.id)
                    }
                }
                .padding(contentPadding)
                .animation(.easeInOut(duration: 0.18), value: store.cards.count)
            }
            .focusable()
            .macOSCardGridFocusStyle()
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
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(tinted ? PasteTheme.accent : Color.secondary)
                .frame(width: 82, height: 82)
                .background(PasteTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(PasteTheme.border, lineWidth: 1))
                .rotationEffect(.degrees(-5))

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if selectedFilter != .all || selectedTimeFilter != .all || !searchText.isEmpty {
                Button(l.resetFilters) {
                    selectedFilter = .all
                    selectedTimeFilter = .all
                    clearSearch()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PasteTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PasteTheme.accent.opacity(0.09), in: Capsule())
            }
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
    @FocusState private var focusedAction: CardAction?

    private enum CardAction: Hashable {
        case favorite, delete, copy
    }

    let card: ClipboardCard
    /// 由外部统一驱动的“当前时间”，保证相对时间文案会随时间刷新
    let now: Date
    let shortcutNumber: Int?
    let isSelected: Bool
    let isAutoPasteEnabled: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    private var l: L { settings.l }
    private let thumbnailHeight: CGFloat = 116
    private let defaultTextLineLimit = 5

    private var showsActions: Bool {
        isHovered || isSelected || focusedAction != nil
    }

    private var borderColor: Color {
        if isSelected { return PasteTheme.accent.opacity(0.85) }
        if isHovered { return PasteTheme.accent.opacity(0.4) }
        return PasteTheme.border.opacity(0.8)
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.5 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 来源与时间在一处呈现，操作按钮在悬停或选中时突出。
            HStack(spacing: 8) {
                sourceIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.sourceAppName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text(l.relativeTimeSince(card.createdAt, now: now, fallbackToDateAfterDays: 7))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                HStack(spacing: 4) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: card.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundStyle(card.isFavorite ? Color.orange : Color.secondary)
                            .frame(width: 23, height: 25)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedAction, equals: .favorite)
                    .opacity(card.isFavorite || showsActions ? 1 : 0)
                    .platformHelp(card.isFavorite ? l.unfavorite : l.favorite)
                    .accessibilityLabel(card.isFavorite ? l.unfavorite : l.favorite)
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 23, height: 25)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedAction, equals: .delete)
                    .opacity(showsActions ? 1 : 0)
                    .platformHelp(l.delete)
                    .accessibilityLabel(l.delete)
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 6) {
                Image(systemName: card.kind.symbolName)
                    .font(.system(size: 10))
                    .foregroundStyle(PasteTheme.accent.opacity(0.8))
                Text(contentMetaText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let shortcutNumber {
                    Text("⌘\(shortcutNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .opacity(showsActions ? 0 : 0.7)
                        .accessibilityHidden(true)
                }
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(PasteTheme.accent)
                        .frame(width: 25, height: 22)
                        .background(PasteTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .focused($focusedAction, equals: .copy)
                .opacity(showsActions ? 1 : 0)
                .platformHelp(l.copy)
                .accessibilityLabel(l.copy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 232, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 14))
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
                .fill(PasteTheme.surface)
                .shadow(
                    color: .black.opacity(isHovered ? 0.07 : 0.025),
                    radius: isHovered ? 12 : 4,
                    y: isHovered ? 4 : 2
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
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            smartContentView
        case .url:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PasteTheme.accent)
                    Text(URL(string: card.previewText)?.host ?? l.kindURL)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                Text(card.previewText)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: thumbnailHeight, alignment: .topLeading)
            .background(PasteTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
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
                .font(.system(size: 14))
                .lineSpacing(4)
                .lineLimit(defaultTextLineLimit)
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .frame(maxWidth: .infinity)
            .frame(height: thumbnailHeight)
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
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(iconColor.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)

            Text(text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: thumbnailHeight)
        .background(iconColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
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
                .frame(width: 26, height: 26)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(sourceBadgeColor.opacity(0.16))
                .frame(width: 26, height: 26)
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
