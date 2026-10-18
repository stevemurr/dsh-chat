import AppKit
import SwiftUI

enum ChatTheme {
    static let text = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let muted = adaptive(light: .black.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.50))
    static let accent = adaptive(
        light: NSColor(red: 0.08, green: 0.39, blue: 0.46, alpha: 1),
        dark: NSColor(red: 0.47, green: 0.79, blue: 0.85, alpha: 1)
    )
    static let border = adaptive(light: .black.withAlphaComponent(0.11), dark: .white.withAlphaComponent(0.10))
    static let background = adaptive(
        light: NSColor(white: 0.97, alpha: 1),
        dark: NSColor(red: 0.105, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let sidebar = adaptive(light: .black.withAlphaComponent(0.035), dark: .black.withAlphaComponent(0.13))
    static let composer = adaptive(light: .white.withAlphaComponent(0.80), dark: .black.withAlphaComponent(0.12))
    static let surface = adaptive(light: .black.withAlphaComponent(0.035), dark: .white.withAlphaComponent(0.04))
    static let hover = adaptive(light: .black.withAlphaComponent(0.055), dark: .white.withAlphaComponent(0.065))
    static let selection = adaptive(light: .black.withAlphaComponent(0.085), dark: .white.withAlphaComponent(0.10))
    static let codeBackground = adaptive(light: .white.withAlphaComponent(0.65), dark: .black.withAlphaComponent(0.16))
    static let warning = adaptive(light: NSColor(red: 0.66, green: 0.31, blue: 0.02, alpha: 1), dark: .systemOrange)
    static let sendForeground = adaptive(light: .white, dark: NSColor(red: 0.08, green: 0.16, blue: 0.18, alpha: 1))
    static let disabledForeground = Color(nsColor: .disabledControlTextColor)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct BrandMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "bubble.left.and.text.bubble.right")
            .font(.system(size: size * 0.54, weight: .medium))
            .foregroundStyle(ChatTheme.accent)
            .frame(width: size, height: size)
            .background(ChatTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(ChatTheme.accent.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    @State private var hovered = false

    // These SF Symbols have different optical spacing inside their font bounds.
    // Adjust only the glyph; every button keeps the same centered hit area.
    private var symbolVerticalOffset: CGFloat {
        switch symbol {
        case "pin", "pin.fill": 1
        case "square.and.pencil": -1
        default: 0
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? ChatTheme.accent : hovered ? ChatTheme.text : ChatTheme.secondary)
                .offset(y: symbolVerticalOffset)
                .frame(width: 29, height: 28)
                .background(hovered || selected ? ChatTheme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovered = $0 }
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(ChatTheme.secondary)
            .padding(.horizontal, 5)
            .frame(height: 19)
            .background(ChatTheme.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ChatTheme.border))
    }
}
