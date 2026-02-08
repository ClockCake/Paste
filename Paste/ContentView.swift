//
//  ContentView.swift
//  Paste
//
//  Created by 黄尧栋 on 2026/2/8.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClipboardStore
    @State private var showingClearAllAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste")
                        .font(.largeTitle.weight(.semibold))
                    Text("Auto capture clipboard with iCloud sync")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Text("\(store.totalItems) items")
                        Text(store.storageText)
                        Text(store.cloudSyncEnabled ? "iCloud On" : "iCloud Off (local only)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    showingClearAllAlert = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(store.totalItems == 0)
            }

            Picker("Filter", selection: $store.filter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            if store.cards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No clipboard history yet")
                        .foregroundStyle(.secondary)
                    Text("Copy Text / URL / Image to start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(store.cards) { card in
                            ClipboardCardView(
                                card: card,
                                onCopy: {
                                    store.copy(card)
                                },
                                onDelete: {
                                    store.delete(card)
                                }
                            )
                            .environmentObject(store)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 520)
        .alert("Clear all clipboard history?", isPresented: $showingClearAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("This removes all local history and cached thumbnails.")
        }
    }
}

private struct ClipboardCardView: View {
    @EnvironmentObject private var store: ClipboardStore

    let card: ClipboardCard
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.kind.title, systemImage: card.kind.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }

            content

            Spacer(minLength: 4)

            Text(card.sourceAppName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(card.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 260, height: 220, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onCopy)
        .help("Click to copy back to clipboard")
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
