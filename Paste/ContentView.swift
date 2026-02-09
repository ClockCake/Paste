import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @State private var showingClearAllAlert = false
    @State private var showingRestartAlert = false

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
            .onChange(of: settings.iCloudSyncPreference) { _, _ in
                showingRestartAlert = true
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
        Picker(l.filterAll, selection: $store.filter) {
            ForEach(ClipboardFilter.allCases) { filter in
                Text(filter.localizedTitle(l)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
    }

    // MARK: - Card Area

    private var cardArea: some View {
        Group {
            if store.cards.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(store.cards) { card in
                            ClipboardCardView(
                                card: card,
                                onCopy: { store.copy(card) },
                                onDelete: { store.delete(card) }
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
}

// MARK: - Card View

private struct ClipboardCardView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @State private var isHovered = false

    let card: ClipboardCard
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var l: L { settings.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.kind.localizedTitle(l), systemImage: card.kind.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .opacity(isHovered ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .help(l.delete)
            }

            content

            Spacer(minLength: 4)

            HStack {
                Text(card.sourceAppName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Text(card.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(width: 260, height: 220, alignment: .topLeading)
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
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onCopy)
        .help(l.clickToCopy)
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            Text(card.previewText)
                .font(.body)
                .lineLimit(6)
                .textSelection(.enabled)
        case .url:
            Text(card.previewText)
                .font(.body)
                .lineLimit(4)
                .foregroundStyle(.blue)
                .textSelection(.enabled)
        case .image:
            CachedThumbnailView(key: card.thumbnailKey)
                .environmentObject(store)
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Thumbnail View

private struct CachedThumbnailView: View {
    @EnvironmentObject private var store: ClipboardStore

    let key: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.3))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: key) {
            image = store.thumbnail(forKey: key)
        }
    }
}
