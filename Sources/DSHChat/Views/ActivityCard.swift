import SwiftUI

enum ActivityCardStatus {
    case running
    case complete
    case failed

    fileprivate var color: Color {
        switch self {
        case .running: ChatTheme.accent
        case .complete: ChatTheme.secondary
        case .failed: ChatTheme.warning
        }
    }

    fileprivate var accessibilityDescription: String {
        switch self {
        case .running: "In progress"
        case .complete: "Complete"
        case .failed: "Failed"
        }
    }
}

struct ActivityCard<Content: View>: View {
    let title: String
    let symbol: String
    let status: ActivityCardStatus
    let expandable: Bool
    private let content: Content
    @State private var isExpanded: Bool
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    init(
        title: String,
        symbol: String,
        status: ActivityCardStatus,
        expandable: Bool = true,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.status = status
        self.expandable = expandable
        self.content = content()
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expandable {
                Button {
                    isExpanded.toggle()
                } label: {
                    header
                        .background(isHovered || isFocused ? ChatTheme.hover : .clear)
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($isFocused)
                .onHover { isHovered = $0 }
                .onKeyPress(.rightArrow) {
                    isExpanded = true
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    isExpanded = false
                    return .handled
                }
                .accessibilityLabel(title)
                .accessibilityValue("\(status.accessibilityDescription), \(isExpanded ? "expanded" : "collapsed")")
                .accessibilityHint(isExpanded ? "Collapse activity details" : "Expand activity details")
                .help(isExpanded ? "Hide details" : "Show details")
            } else {
                header
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(status.accessibilityDescription)
            }

            if expandable && isExpanded {
                Rectangle()
                    .fill(ChatTheme.border)
                    .frame(height: 1)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ChatTheme.border))
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 8)
                .opacity(expandable ? 1 : 0)
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            statusIndicator
                .frame(width: 16, height: 16)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .running:
            ActivitySpinner()
        case .complete:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .medium))
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
        }
    }
}

private struct ActivitySpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.86)
            .stroke(ChatTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                reduceMotion ? nil : .linear(duration: 0.8).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear { isAnimating = !reduceMotion }
            .onChange(of: reduceMotion) { _, value in isAnimating = !value }
            .accessibilityLabel("In progress")
    }
}
