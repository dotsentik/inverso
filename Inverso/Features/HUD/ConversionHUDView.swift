import SwiftUI

/// The HUD capsule: input → output · layout code, or a hint.
struct ConversionHUDView: View {
    let content: ConversionHUDContent
    let background: HUDBackgroundStyle

    var body: some View {
        HStack(spacing: 8) {
            if let message = content.message {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Text(message)
            } else {
                Text(content.input)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text(content.output)
                    .fontWeight(.semibold)
                if !content.layoutCode.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(content.layoutCode)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.title3)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .modifier(HUDBackground(style: background))
        .padding(12)  // Room for the shadow inside the panel
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spokenText)
    }
}

private struct HUDBackground: ViewModifier {
    let style: HUDBackgroundStyle

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: .capsule)
            } else {
                content.background(.regularMaterial, in: Capsule())
            }
        case .material:
            content
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        case .solid:
            content
                .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}
