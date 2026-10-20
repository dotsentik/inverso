import SwiftUI

extension View {
    /// A section fills the fixed settings area; its content scrolls inside if it does not fit.
    func settingsTabFrame() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A Form section: fills the area, the Form scrolls by itself.
    func settingsFormFrame() -> some View {
        settingsTabFrame()
    }
}
