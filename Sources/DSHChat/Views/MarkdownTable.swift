import SwiftUI

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        if !headers.isEmpty {
            ScrollView(.horizontal) {
                WrappingTableLayout(columnCount: headers.count) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header).fontWeight(.semibold)
                    }
                    Rectangle().fill(ChatTheme.border).frame(height: 1)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        ForEach(headers.indices, id: \.self) { column in
                            cell(column < row.count ? row[column] : "")
                        }
                    }
                }
                .containerRelativeFrame(.horizontal) { width, _ in
                    max(width - 28, WrappingTableLayout.minimumWidth(columns: headers.count))
                }
                .padding(14)
                .overlayScrollbars()
            }
            .font(.system(size: 14))
            .lineSpacing(4)
            .background(ChatTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ChatTheme.border))
        }
    }

    private func cell(_ text: String) -> some View {
        Text(ChatMarkdown.inline(text))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Measures every cell at its column's width, so long text increases the row's
/// height instead of increasing the width of the entire table.
private struct WrappingTableLayout: Layout {
    let columnCount: Int
    private static let columnSpacing: CGFloat = 18
    private let rowSpacing: CGFloat = 10

    static func minimumWidth(columns: Int) -> CGFloat {
        CGFloat(columns) * 96 + CGFloat(max(0, columns - 1)) * columnSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let metrics = measure(width: proposal.width, subviews: subviews)
        return CGSize(width: metrics.width, height: metrics.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = measure(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in metrics.rows {
            var x = bounds.minX
            for (column, index) in row.indices.enumerated() {
                let width = row.isDivider ? metrics.width : metrics.columns[column]
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: width, height: row.height))
                x += width + Self.columnSpacing
            }
            y += row.height + rowSpacing
        }
    }

    private func measure(width proposedWidth: CGFloat?, subviews: Subviews) -> Metrics {
        var preferred = Array(repeating: CGFloat(96), count: columnCount)
        for index in subviews.indices where index != columnCount {
            let column = (index > columnCount ? index - 1 : index) % columnCount
            let ideal = subviews[index].sizeThatFits(.unspecified).width
            preferred[column] = max(preferred[column], min(ideal, 420))
        }
        let gaps = CGFloat(columnCount - 1) * Self.columnSpacing
        let width = max(proposedWidth ?? (preferred.reduce(0, +) + gaps), Self.minimumWidth(columns: columnCount))
        let available = width - gaps
        let surplus = max(0, available - CGFloat(columnCount) * 96)
        let demand = preferred.map { $0 - 96 }
        let totalDemand = demand.reduce(0, +)
        let columns = preferred.indices.map { column -> CGFloat in
            if available >= preferred.reduce(0, +) {
                return preferred[column] + (available - preferred.reduce(0, +)) / CGFloat(columnCount)
            }
            return 96 + surplus * (totalDemand > 0 ? demand[column] / totalDemand : 1 / CGFloat(columnCount))
        }

        var rows: [Row] = []
        var start = 0
        while start < subviews.count {
            let isDivider = start == columnCount
            let end = min(subviews.count, start + (isDivider ? 1 : columnCount))
            let indices = Array(start..<end)
            let height = indices.enumerated().map { column, index in
                subviews[index].sizeThatFits(ProposedViewSize(width: isDivider ? width : columns[column], height: nil)).height
            }.max() ?? 0
            rows.append(Row(indices: indices, height: height, isDivider: isDivider))
            start = end
        }
        return Metrics(width: width, columns: columns, rows: rows,
                       height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing)
    }

    private struct Row {
        let indices: [Int]
        let height: CGFloat
        let isDivider: Bool
    }

    private struct Metrics {
        let width: CGFloat
        let columns: [CGFloat]
        let rows: [Row]
        let height: CGFloat
    }
}
