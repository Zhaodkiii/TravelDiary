import SwiftUI

struct OutlinedButtonStyle: ButtonStyle {
    var tint: Color = Color(uiColor: .separator)
    var hover: Color = Color(uiColor: .tertiarySystemFill)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? hover : Color(uiColor: .secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
