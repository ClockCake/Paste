#if os(macOS)
import SwiftUI

// MARK: - 快捷键设置视图

/// 快捷键录入面板：让用户录制自定义快捷键组合
struct HotkeySettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @State private var isRecording = false
    @State private var recordingMonitor: Any?

    private var l: L { settings.l }

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(l.hotkeyTitle)
                    .font(.headline)
                Spacer()
            }

            // 当前快捷键显示
            HStack {
                Text(l.hotkeyCurrentLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                if let hotkey = hotkeyManager.currentHotkey {
                    Text(hotkey.displayString)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.quaternary)
                        }
                } else {
                    Text(l.hotkeyNotSet)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // 操作按钮
            HStack(spacing: 10) {
                // 录制按钮
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isRecording ? Color.red : Color.accentColor)
                            .frame(width: 8, height: 8)
                        Text(isRecording ? l.hotkeyRecording : l.hotkeyRecord)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .accentColor)
                .controlSize(.regular)

                // 清除按钮
                Button(role: .destructive) {
                    hotkeyManager.clearHotkey()
                } label: {
                    Text(l.hotkeyClear)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(hotkeyManager.currentHotkey == nil)
            }

            // 提示文字
            if isRecording {
                Text(l.hotkeyRecordingHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            } else {
                Text(l.hotkeyHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 280)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - 录制逻辑

    /// 开始监听按键事件
    private func startRecording() {
        isRecording = true

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC 键取消录制
            if event.keyCode == 0x35 {
                stopRecording()
                return nil
            }

            // 从 NSEvent 创建 HotkeyConfig（自动转换为 Carbon 修饰键格式）
            guard let config = HotkeyConfig.from(event: event) else {
                return nil  // 没有修饰键，忽略
            }

            hotkeyManager.setHotkey(config)
            stopRecording()
            return nil
        }
    }

    /// 停止监听
    private func stopRecording() {
        isRecording = false
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
    }
}
#endif
