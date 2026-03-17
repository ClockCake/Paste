import SwiftUI

/// 日期范围选择弹窗（仅 macOS 端使用）
/// 支持两种模式：筛选模式（应用日期范围筛选）和删除模式（按日期范围批量删除）
#if os(macOS)
enum DatePickerMode {
    case filter   // 筛选模式
    case delete   // 删除模式
}

struct DatePickerSheet: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: SettingsManager
    @Binding var isPresented: Bool

    let mode: DatePickerMode

    /// 筛选模式的回调：传入 from/to 日期
    var onApplyFilter: ((Date, Date) -> Void)?

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var recordCount: Int = 0
    @State private var showingDeleteConfirm = false
    @State private var deleteResultMessage: String?

    private var l: L { settings.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: mode == .delete ? "trash.circle" : "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(mode == .delete ? .red : .accentColor)
                Text(mode == .delete ? l.deleteByDate : l.selectDateRange)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // 日期选择器
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(
                    l.startDate,
                    selection: $startDate,
                    in: ...endDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.field)

                DatePicker(
                    l.endDate,
                    selection: $endDate,
                    in: startDate...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.field)
            }

            Divider()

            // 记录数预览
            HStack {
                if recordCount > 0 {
                    Label(
                        l.itemCount(recordCount),
                        systemImage: "doc.text"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        l.noRecordsInRange,
                        systemImage: "tray"
                    )
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            // 删除结果提示
            if let resultMessage = deleteResultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Divider()

            // 操作按钮
            HStack {
                Button(l.cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if mode == .delete {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label(l.delete, systemImage: "trash")
                    }
                    .disabled(recordCount == 0)
                } else {
                    Button {
                        onApplyFilter?(startDate, endDate)
                        isPresented = false
                    } label: {
                        Label(l.applyFilter, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(recordCount == 0)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            refreshCount()
        }
        .onChange(of: startDate) { _ in
            refreshCount()
        }
        .onChange(of: endDate) { _ in
            refreshCount()
        }
        .alert(l.deleteConfirmByDate, isPresented: $showingDeleteConfirm) {
            Button(l.cancel, role: .cancel) {}
            Button(l.delete, role: .destructive) {
                performDelete()
            }
        } message: {
            Text(l.deleteConfirmByDateMessage(recordCount))
        }
    }

    private func refreshCount() {
        recordCount = store.countByDateRange(from: startDate, to: endDate)
    }

    private func performDelete() {
        let deleted = store.deleteByDateRange(from: startDate, to: endDate)
        withAnimation(.easeInOut(duration: 0.2)) {
            deleteResultMessage = l.deleteSuccess(deleted)
        }
        refreshCount()
        // 延迟关闭弹窗
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isPresented = false
        }
    }
}
#endif
