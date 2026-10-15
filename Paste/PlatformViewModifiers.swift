import SwiftUI

extension View {
    /// 网格已有逐卡片选中态，新系统上避免再绘制包住整个滚动区的焦点边框。
    @ViewBuilder
    func macOSCardGridFocusStyle() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    @ViewBuilder
    func platformHelp(_ text: String) -> some View {
        self.help(text)
    }

    @ViewBuilder
    func macOSBorderlessMenuStyle() -> some View {
        self.menuStyle(.borderlessButton)
            .fixedSize()
    }

    @ViewBuilder
    func platformOnHover(_ perform: @escaping (Bool) -> Void) -> some View {
        self.onHover(perform: perform)
    }

    @ViewBuilder
    func platformOnExitCommand(_ action: @escaping () -> Void) -> some View {
        self.onExitCommand(perform: action)
    }
}
