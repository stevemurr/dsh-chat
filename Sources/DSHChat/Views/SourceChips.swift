import SwiftUI

struct SourceChips: View {
    let sources: [MarkdownSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Sources")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChatTheme.secondary)
            SourceChipFlow(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(sources) { source in
                    SourceChip(source: source)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.disabled)
    }
}

private struct SourceChip: View {
    let source: MarkdownSource
    @Environment(\.openURL) private var openURL
    @State private var hovered = false
    @FocusState private var focused: Bool

    private var domain: String {
        source.host.hasPrefix("www.") ? String(source.host.dropFirst(4)) : source.host
    }

    private var siteColor: Color {
        let colors: [Color] = [.teal, .blue, .purple, .indigo, .orange, .pink]
        let index = domain.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }
        return colors[index]
    }

    var body: some View {
        Button {
            guard ["https", "http"].contains(source.url.scheme?.lowercased() ?? "") else { return }
            openURL(source.url)
        } label: {
            HStack(spacing: 7) {
                Text(String(domain.first ?? "?").uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(siteColor)
                    .frame(width: 22, height: 22)
                    .background(siteColor.opacity(0.13), in: Circle())
                    .overlay(Circle().strokeBorder(siteColor.opacity(0.12)))
                    .accessibilityHidden(true)
                Text(domain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovered ? ChatTheme.text : ChatTheme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 5)
            .padding(.trailing, 11)
            .frame(height: 34)
            .background(hovered ? ChatTheme.hover : ChatTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? ChatTheme.accent : ChatTheme.border, lineWidth: focused ? 2 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .focused($focused)
        .focusEffectDisabled()
        .help("\(source.detail ?? source.title)\n\(source.url.absoluteString)")
        .accessibilityLabel("\(source.detail ?? source.title), \(domain)")
        .accessibilityHint("Open source in your browser")
        .onHover { hovered = $0 }
    }
}

/// Keeps each chip intact, moving it to the next row when the answer gets narrow.
private struct SourceChipFlow: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(proposedWidth: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(proposedWidth: bounds.width, subviews: subviews)
        for (index, item) in result.items.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func arrangement(proposedWidth: CGFloat?, subviews: Subviews) -> Arrangement {
        let width = proposedWidth.flatMap { $0.isFinite ? max(0, $0) : nil }
        var items: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let idealSize = subview.sizeThatFits(.unspecified)
            let itemWidth = width.map { min(idealSize.width, $0) } ?? idealSize.width
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if let width, x > 0, x + size.width > width {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            items.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return Arrangement(size: CGSize(width: width ?? usedWidth, height: y + rowHeight), items: items)
    }

    private struct Arrangement {
        let size: CGSize
        let items: [CGRect]
    }
}
