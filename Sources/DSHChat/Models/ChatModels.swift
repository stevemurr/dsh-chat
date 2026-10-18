import DSHProtocol
import Foundation

/// Only metadata lives in this app. The authenticated DSH host owns transcripts.
struct ChatSummary: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var updatedAt: Date
    let hostIdentity: String
    var modelID: String?
}

struct ChatModelOption: Identifiable, Hashable {
    let provider: String
    let model: String
    let name: String
    let reasoningEffort: String?
    var id: String { "\(provider)/\(model)" }
}

struct ChatApproval: Identifiable {
    let id: String
    let request: JSONValue
    let clientID: String
    let generation: UUID

    var name: String { request["toolName"]?.stringValue ?? "Tool" }
    var reason: String {
        request["displayReason"]?["en"]?.stringValue
            ?? request["reason"]?.stringValue
            ?? "DSH would like permission to run this tool."
    }
}

struct ChatQuestion: Identifiable {
    struct Option: Hashable {
        let label: String
        let description: String?
    }
    let id: String
    let text: String
    let options: [Option]
    let multiSelect: Bool
}

struct ChatQuestionRequest: Identifiable {
    let id: String
    let request: JSONValue
    let clientID: String
    let generation: UUID

    /// Reject the complete form if any entry would otherwise be silently
    /// dropped, or if duplicate identities would make the native form ambiguous.
    var isValid: Bool {
        guard let values = request["questions"]?.arrayValue, !values.isEmpty,
              values.count == questions.count else { return false }
        let parsed = questions
        guard Set(parsed.map(\.id)).count == parsed.count else { return false }
        return zip(values, parsed).allSatisfy { value, question in
            guard !question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if let multiple = value["multiSelect"], multiple.boolValue == nil { return false }
            if let options = value["options"] {
                guard let raw = options.arrayValue, raw.count == question.options.count else { return false }
            }
            let labels = question.options.map(\.label)
            return Set(labels).count == labels.count
                && labels.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    var questions: [ChatQuestion] {
        (request["questions"]?.arrayValue ?? []).compactMap { question in
            guard let id = question["id"]?.stringValue,
                  let text = question["question"]?.stringValue else { return nil }
            return ChatQuestion(id: id, text: text, options: (question["options"]?.arrayValue ?? []).compactMap { option in
                option["label"]?.stringValue.map {
                    .init(label: $0, description: option["description"]?.stringValue)
                }
            }, multiSelect: question["multiSelect"]?.boolValue ?? false)
        }
    }
}

/// The SDK has no system-message parameter. Supply app context in a separate
/// text block, then remove only this exact app-authored prefix for presentation.
enum QuickChatPrompt {
    static let opening = "<dsh-quick-chat-context>"
    static let closing = "</dsh-quick-chat-context>\n\n"

    static func text(question: String, webSearch: Bool, firstTurn: Bool) -> String {
        var context = firstTurn
            ? "You are in a lightweight macOS question-and-answer chat. Give useful, concise answers in Markdown. This chat is independent of a workspace. Do not inspect local files or run shell commands unless the user explicitly asks. "
            : ""
        context += webSearch
            ? "Use the host's web search and web fetch tools when current information or verification would help. Link sources you use, and finish web-sourced answers with a Sources section containing Markdown links. If those tools are unavailable, say so clearly; do not imply that you searched."
            : "Web search is switched off for this question. Answer from the conversation and your existing knowledge without browsing. Explain any uncertainty about current information."
        return opening + "\n" + context + "\n" + closing + question
    }

    static func cleaned(_ text: String) -> String {
        guard text.hasPrefix(opening + "\n"), let range = text.range(of: closing) else { return text }
        return String(text[range.upperBound...])
    }
}
