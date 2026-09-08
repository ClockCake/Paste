import SwiftUI

extension View {
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
