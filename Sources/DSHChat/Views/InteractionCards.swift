import DSHProtocol
import SwiftUI

struct ApprovalCard: View {
    let approval: ChatApproval
    let isAnswering: Bool
    let onAnswer: (ApprovalOutcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permission to use \(approval.name)", systemImage: "hand.raised")
                .font(.system(size: 14, weight: .semibold))
            Text(approval.reason).font(.system(size: 13)).foregroundStyle(ChatTheme.secondary).textSelection(.enabled)
            HStack {
                Spacer()
                Button("Deny") { onAnswer(.rejected) }
                Button("Allow Once") { onAnswer(.allowedOnce) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(ChatTheme.sendForeground)
            }.controlSize(.small).disabled(isAnswering)
        }
        .padding(14)
        .foregroundStyle(ChatTheme.text)
        .tint(ChatTheme.accent)
        .background(ChatTheme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ChatTheme.accent.opacity(0.2)))
    }
}

struct QuestionCard: View {
    let request: ChatQuestionRequest
    let isAnswering: Bool
    let onAnswer: ([String: [String]], [String: String]) -> Void
    @State private var selections: [String: [String]] = [:]
    @State private var custom: [String: String] = [:]

    private var complete: Bool {
        !request.questions.isEmpty && request.questions.allSatisfy {
            !(custom[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(selections[$0.id] ?? []).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text).font(.system(size: 14, weight: .semibold))
                    ForEach(question.options, id: \.label) { option in
                        Button {
                            var selected = selections[question.id] ?? []
                            if selected.contains(option.label) { selected.removeAll { $0 == option.label } }
                            else if question.multiSelect { selected.append(option.label) }
                            else { selected = [option.label] }
                            selections[question.id] = selected
                            custom[question.id] = ""
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: (selections[question.id] ?? []).contains(option.label) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ChatTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.label).font(.system(size: 13, weight: .medium))
                                    if let description = option.description {
                                        Text(description).font(.system(size: 12)).foregroundStyle(ChatTheme.secondary)
                                    }
                                }
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    TextField(question.options.isEmpty ? "Your answer" : "Or write your own answer", text: Binding(
                        get: { custom[question.id] ?? "" },
                        set: { custom[question.id] = $0; if !$0.isEmpty { selections[question.id] = [] } }
                    )).textFieldStyle(.roundedBorder).font(.system(size: 14))
                }
            }
            HStack {
                Spacer()
                Button("Continue") { onAnswer(selections, custom) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(ChatTheme.sendForeground)
                    .controlSize(.small).disabled(!complete || isAnswering)
            }
        }
        .padding(14)
        .foregroundStyle(ChatTheme.text)
        .tint(ChatTheme.accent)
        .background(ChatTheme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ChatTheme.accent.opacity(0.2)))
    }
}
