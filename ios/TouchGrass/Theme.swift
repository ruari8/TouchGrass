import SwiftUI

enum Theme {
    static let grass = Color(red: 0.45, green: 0.85, blue: 0.40)
    static let soil = Color(red: 0.06, green: 0.11, blue: 0.08)
    static let locked = Color(red: 0.95, green: 0.45, blue: 0.35)
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.grass

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint, in: .capsule)
            .foregroundStyle(Theme.soil)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
