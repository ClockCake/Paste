import SwiftUI

extension View {
    @ViewBuilder
    func platformHelp(_ text: String) -> some View {
        #if os(macOS)
        self.help(text)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macOSBorderlessMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
            .fixedSize()
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformOnHover(_ perform: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        self.onHover(perform: perform)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformOnExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
