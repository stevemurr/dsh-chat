import DSHKit
import DSHSession
import XCTest
@testable import DSHChat

final class LiveHostTests: XCTestCase {
    /// Opt in locally. This authenticates and lists models, without creating a
    /// session, sending a prompt, or invoking a model/tool.
    func testLocalDSHAuthenticationAndModelCatalog() async throws {
        guard ProcessInfo.processInfo.environment["DSH_CHAT_LIVE_CHECK"] == "1" else {
            throw XCTSkip("Set DSH_CHAT_LIVE_CHECK=1 to check the local DSH host")
        }
        let connection = DSHConnection()
        do {
            let connected = try await connection.connected()
            let catalog = try await connected.client.modelCatalog()
            XCTAssertFalse(connected.identity.isEmpty)
            XCTAssertFalse(connected.identity.contains("token="))
            XCTAssertFalse(catalog.groups.isEmpty, "The local DSH host needs at least one configured model provider")
            await connection.disconnect()
        } catch {
            await connection.disconnect()
            throw error
        }
    }

    /// Opt in separately because this creates one real host session and invokes
    /// its configured model and web tools. Permission requests are never approved.
    @MainActor
    func testLiveWebQuestion() async throws {
        guard ProcessInfo.processInfo.environment["DSH_CHAT_LIVE_QUESTION"] == "1" else {
            throw XCTSkip("Set DSH_CHAT_LIVE_QUESTION=1 to ask one public web question")
        }
        let suite = "DSHChatLiveQuestion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let connection = DSHConnection()
        let model = ChatModel(connection: connection, defaults: defaults)
        var searchObserved = false
        var assistantPresent = false
        var pendingDecision = false
        var terminal = false
        defer {
            print("Live web question: searchObserved=\(searchObserved), assistantPresent=\(assistantPresent), pendingDecision=\(pendingDecision), terminal=\(terminal)")
            model.close()
            defaults.removePersistentDomain(forName: suite)
        }

        do {
            model.webSearchEnabled = true
            model.draft = "Search the web for the official Raycast website. Reply in one sentence with a link."
            model.send()
            let deadline = Date().addingTimeInterval(90)
            while Date() < deadline {
                searchObserved = searchObserved || model.timeline.items.contains { item in
                    guard case .tool(let tool) = item.content else { return false }
                    let name = tool.name.lowercased()
                    return [.webSearch, .webFetch].contains(ToolActivity(toolName: tool.name))
                        || name.contains("web_search") || name.contains("web_fetch") || name.contains("search_service")
                }
                assistantPresent = model.timeline.items.contains { item in
                    guard case .assistant(let text) = item.content else { return false }
                    return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                pendingDecision = !model.approvals.isEmpty || !model.questions.isEmpty || model.hasUnsupportedQuestions
                if pendingDecision {
                    throw XCTSkip("The live host requested a user decision; the test stopped the turn without answering it")
                }
                if let error = model.errorMessage, !model.isSubmitting, !model.isConnecting {
                    throw LiveQuestionError.host(error)
                }
                if model.selectedSessionID != nil, !model.isBusy {
                    terminal = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            if !terminal { await cancelLiveTurn(model: model, connection: connection) }
            await connection.disconnect()
            XCTAssertTrue(terminal, "The live question did not finish within 90 seconds")
            XCTAssertTrue(assistantPresent, "The host finished without a visible assistant answer")
            XCTAssertTrue(searchObserved, "No web-search or web-fetch tool was observed on this host")
            let answer = model.timeline.items.compactMap { item -> String? in
                guard case .assistant(let text) = item.content else { return nil }
                return text
            }.joined(separator: "\n")
            XCTAssertTrue(answer.contains("https://www.raycast.com") || answer.contains("https://raycast.com"), "The answer should link to the official Raycast website")
        } catch {
            await cancelLiveTurn(model: model, connection: connection)
            await connection.disconnect()
            throw error
        }
    }

    @MainActor
    private func cancelLiveTurn(model: ChatModel, connection: DSHConnection) async {
        guard let id = model.selectedSessionID, model.isBusy,
              let connected = try? await connection.connected() else { return }
        try? await connected.client.cancel(sessionId: id)
    }

    private enum LiveQuestionError: LocalizedError {
        case host(String)
        var errorDescription: String? { if case .host(let message) = self { return message }; return nil }
    }
}
