import DSHKit
import DSHProtocol
import XCTest
@testable import DSHChat

@MainActor
final class ChatModelTests: XCTestCase {
    func testConnectionIsReadOnlyUntilFirstSendAndStreamsWorkspaceFreeChat() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        fixture.model.reconnect()
        try await waitUntil { fixture.model.isConnected }
        let initialCreateCount = await fixture.transport.count("session/create")
        XCTAssertEqual(initialCreateCount, 0)

        fixture.model.draft = "What is a neutron star?"
        fixture.model.send()
        try await waitUntil { !fixture.model.isSubmitting && fixture.model.pendingPrompt == nil }
        let createCall = await fixture.transport.lastCall("session/create")
        let create = try XCTUnwrap(createCall)
        XCTAssertEqual(create.args["request"], .object([:]))
        let promptCall = await fixture.transport.lastCall("session/prompt")
        let prompt = try XCTUnwrap(promptCall)
        let wire = try XCTUnwrap(prompt.args["request"]?["content"]?[0]?["text"]?.stringValue)
        XCTAssertTrue(wire.contains("web search"))
        XCTAssertEqual(fixture.model.cleanedUserText(wire), "What is a neutron star?")
        XCTAssertTrue(fixture.model.isBusy)
        XCTAssertEqual(fixture.model.history.first?.title, "What is a neutron star?")

        await fixture.transport.emit("session/follow", ["type": "assistant-stream", "frame": ["type": "start", "attemptId": "answer", "turn": 1, "step": 1]])
        await fixture.transport.emit("session/follow", ["type": "assistant-stream", "frame": ["type": "chunk", "attemptId": "answer", "index": 0,
            "chunk": ["type": "text-delta", "index": 0, "text": "A dense stellar remnant."]]])
        try await waitUntil { fixture.model.timeline.live?.text == "A dense stellar remnant." }
        await fixture.transport.emit("session/follow", Self.event("assistant/message", seq: 3, data: ["message": ["content": [["type": "text", "text": "A dense stellar remnant."]]]]))
        await fixture.transport.emit("session/follow", Self.event("turn/end", seq: 4, data: ["turn": 1]))
        try await waitUntil { !fixture.model.isBusy }
        XCTAssertNil(fixture.model.timeline.live)
        XCTAssertTrue(fixture.model.timeline.items.contains { if case .assistant(let text) = $0.content { return text == "A dense stellar remnant." }; return false })

        fixture.model.webSearchEnabled = false
        fixture.model.draft = "Explain more simply."
        fixture.model.send()
        try await waitUntil { !fixture.model.isSubmitting }
        let secondCall = await fixture.transport.lastCall("session/prompt")
        let second = try XCTUnwrap(secondCall)
        XCTAssertTrue(second.args["request"]?["content"]?[0]?["text"]?.stringValue?.contains("Web search is switched off") == true)
        let finalCreateCount = await fixture.transport.count("session/create")
        XCTAssertEqual(finalCreateCount, 1)
    }

    func testApprovalGenerationAndQuestionAnswersUseHostSchema() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        fixture.model.draft = "Question"
        fixture.model.send()
        try await waitUntil { fixture.model.isConnected && !fixture.model.isSubmitting }
        await fixture.transport.emit("$events", ["type": "waterfall", "event": "approval/request", "eventId": "permission", "agentId": "chat-1", "request": ["toolName": "web_search"]])
        try await waitUntil { fixture.model.approvals.count == 1 }
        let stale = try XCTUnwrap(fixture.model.approvals.first)
        await fixture.transport.emit("$events", ["type": "ready", "clientId": "second-generation"])
        try await waitUntil { fixture.model.approvals.isEmpty }
        fixture.model.answer(stale, outcome: .allowedOnce)
        let resultCount = await fixture.transport.count("$events/result")
        XCTAssertEqual(resultCount, 0)

        await fixture.transport.emit("$events", ["type": "waterfall", "event": "user-questions/request", "eventId": "questions", "agentId": "chat-1",
            "request": ["questions": [["id": "scope", "question": "Which scope?", "multiSelect": true,
                "options": [["label": "Stars"], ["label": "Planets"]]]]]])
        try await waitUntil { fixture.model.questions.count == 1 }
        let request = try XCTUnwrap(fixture.model.questions.first)
        fixture.model.answer(request, selections: ["scope": ["Stars", "Planets"]], custom: ["scope": "Keep it brief"])
        try await waitUntil { fixture.model.questions.isEmpty && !fixture.model.isAnswering }
        let answerCall = await fixture.transport.lastCall("$events/result")
        let answer = try XCTUnwrap(answerCall)
        XCTAssertEqual(answer.args["clientId"]?.stringValue, "second-generation")
        XCTAssertEqual(answer.args["outcome"]?["value"]?["answers"]?[0]?["selected"], ["Stars", "Planets"])
        XCTAssertEqual(answer.args["outcome"]?["value"]?["answers"]?[0]?["custom"], "Keep it brief")
    }

    func testPersistedSessionCannotBeSentToDifferentHost() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        let summary = ChatSummary(id: "old-chat", title: "A saved chat", updatedAt: Date(), hostIdentity: "http://localhost:1111", modelID: nil)
        fixture.defaults.set(try JSONEncoder().encode([summary]), forKey: "DSHChat.history.v1")
        let reopened = ChatModel(connection: fixture.connection, defaults: fixture.defaults)
        defer { reopened.close() }
        reopened.openChat(id: "old-chat")
        try await waitUntil { reopened.errorMessage != nil }
        XCTAssertTrue(reopened.errorMessage?.contains("another DSH host") == true)
        let createCount = await fixture.transport.count("session/create")
        let promptCount = await fixture.transport.count("session/prompt")
        let followCount = await fixture.transport.streamCount("session/follow")
        XCTAssertEqual(createCount, 0)
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(followCount, 0)
    }

    func testPromptCleanupLeavesUserTextUntouched() {
        let question = "A question containing </dsh-quick-chat-context> in its text"
        XCTAssertEqual(QuickChatPrompt.cleaned(QuickChatPrompt.text(question: question, webSearch: true, firstTurn: true)), question)
        XCTAssertEqual(QuickChatPrompt.cleaned("Ordinary text with \(QuickChatPrompt.closing) inside"), "Ordinary text with \(QuickChatPrompt.closing) inside")
    }

    func testModelSelectionRetriesAfterSessionCreationFailure() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        await fixture.transport.setCatalog(["default": ["provider": "test", "model": "small"],
            "groups": [["id": "test", "name": "Test", "models": [["id": "small", "name": "Small"]]]]])
        fixture.model.reconnect()
        try await waitUntil { fixture.model.isConnected }
        await fixture.transport.failNextModelSelection()
        fixture.model.draft = "Hello"
        fixture.model.send()
        try await waitUntil { !fixture.model.isSubmitting && fixture.model.errorMessage != nil }
        XCTAssertEqual(fixture.model.draft, "Hello")
        let failedPromptCount = await fixture.transport.count("session/prompt")
        XCTAssertEqual(failedPromptCount, 0)

        fixture.model.send()
        try await waitUntil { !fixture.model.isSubmitting && fixture.model.pendingPrompt == nil }
        let selectionCount = await fixture.transport.count("session/selectModel")
        let createCount = await fixture.transport.count("session/create")
        let promptCount = await fixture.transport.count("session/prompt")
        XCTAssertEqual(selectionCount, 2)
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(promptCount, 1)
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testReconnectClearsAcknowledgedPromptEvenWhenSnapshotOmitsOldUserRecord() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        await fixture.transport.setEchoPrompts(false)
        fixture.model.draft = "A question with a delayed echo"
        fixture.model.send()
        try await waitUntil { fixture.model.isConnected && !fixture.model.isSubmitting }
        XCTAssertNotNil(fixture.model.pendingPrompt)
        XCTAssertTrue(fixture.model.isBusy)
        await fixture.transport.failStreams("session/follow")
        try await waitUntil { !fixture.model.isConnected }
        await fixture.transport.setSnapshot(["type": "snapshot", "header": [:], "cursor": 50,
            "records": [], "hasMore": true, "projections": [:]])
        fixture.model.reconnect()
        try await waitUntil { fixture.model.isConnected }
        XCTAssertNil(fixture.model.pendingPrompt)
        XCTAssertFalse(fixture.model.isBusy)
        XCTAssertTrue(fixture.model.canStartNewChat)
        let promptCount = await fixture.transport.count("session/prompt")
        XCTAssertEqual(promptCount, 1, "Reconnect must not resubmit an acknowledged prompt")
    }

    func testMalformedQuestionsNeverRenderOrSubmitPartialAnswersAndCanBeStopped() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        fixture.model.draft = "Question"
        fixture.model.send()
        try await waitUntil { fixture.model.isConnected && !fixture.model.isSubmitting }
        await fixture.transport.emit("$events", ["type": "waterfall", "event": "user-questions/request", "eventId": "malformed", "agentId": "chat-1",
            "request": ["questions": [["id": "valid", "question": "Visible question"], ["id": "missing-text"]]]])
        try await waitUntil { fixture.model.hasUnsupportedQuestions }
        XCTAssertTrue(fixture.model.questions.isEmpty)
        XCTAssertTrue(fixture.model.canStop)
        XCTAssertTrue(fixture.model.errorMessage?.contains("could not display") == true)
        let resultCount = await fixture.transport.count("$events/result")
        XCTAssertEqual(resultCount, 0, "Malformed forms must not invent or submit partial answers")
        fixture.model.stop()
        try await waitUntil { !fixture.model.isStopping }
        let stopCount = await fixture.transport.count("session/cancel")
        XCTAssertEqual(stopCount, 1)
        await fixture.transport.emit("session/follow", Self.event("turn/end", seq: 3, data: ["turn": 1, "reason": ["kind": "aborted"]]))
        try await waitUntil { !fixture.model.isBusy }
        XCTAssertFalse(fixture.model.hasUnsupportedQuestions)
    }

    func testQuestionValidationRejectsEmptyFormsAndDuplicateIdentities() {
        let forms: [JSONValue] = [[:], ["questions": []],
            ["questions": [["id": "q", "question": "" ]] ],
            ["questions": [["id": "q", "question": "First"], ["id": "q", "question": "Second"]]],
            ["questions": [["id": "q", "question": "Pick", "options": [["label": "Same"], ["label": "Same"]]]]],
            ["questions": [["id": "q", "question": "Pick", "options": "invalid"]]],
        ]
        for form in forms {
            XCTAssertFalse(ChatQuestionRequest(id: "form", request: form, clientID: "client", generation: UUID()).isValid)
        }
    }

    func testRestoredLiveAnswerIsBusyWithoutTurnStartInTruncatedSnapshot() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        let summary = ChatSummary(id: "chat-1", title: "Active chat", updatedAt: Date(), hostIdentity: "http://localhost:2222", modelID: nil)
        fixture.defaults.set(try JSONEncoder().encode([summary]), forKey: "DSHChat.history.v1")
        await fixture.transport.setSnapshot(["type": "snapshot", "header": [:], "cursor": 50, "records": [], "hasMore": true,
            "projections": [:], "assistantStream": ["activeAttempt": ["attemptId": "active", "stream": [
                ["chunk": ["type": "text-delta", "index": 0, "text": "Still answering"]]]]]])
        let reopened = ChatModel(connection: fixture.connection, defaults: fixture.defaults)
        defer { reopened.close() }
        reopened.openChat(id: "chat-1")
        try await waitUntil { reopened.isConnected }
        XCTAssertEqual(reopened.timeline.live?.text, "Still answering")
        XCTAssertFalse(reopened.timeline.running, "The snapshot intentionally omits turn/start")
        XCTAssertTrue(reopened.isBusy)
        XCTAssertTrue(reopened.canStop)
        XCTAssertFalse(reopened.canStartNewChat)
    }

    func testDisconnectBeforePromptRestoresDraftAndAllowsRecovery() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        await fixture.transport.failEventsBeforeNextFollow()
        fixture.model.draft = "Keep this unsent question"
        fixture.model.send()
        try await waitUntil { !fixture.model.isSubmitting && fixture.model.errorMessage != nil }
        XCTAssertEqual(fixture.model.draft, "Keep this unsent question")
        XCTAssertNil(fixture.model.pendingPrompt)
        XCTAssertFalse(fixture.model.isBusy)
        let initialPrompts = await fixture.transport.count("session/prompt")
        XCTAssertEqual(initialPrompts, 0)
        fixture.model.send()
        try await waitUntil { fixture.model.isConnected && !fixture.model.isSubmitting && fixture.model.pendingPrompt == nil }
        let finalPrompts = await fixture.transport.count("session/prompt")
        XCTAssertEqual(finalPrompts, 1)
    }

    func testOldDecisionResultDoesNotClearNewEventsClientRequest() async throws {
        let fixture = makeFixture()
        defer { fixture.model.close() }
        fixture.model.draft = "Question"
        fixture.model.send()
        try await waitUntil { fixture.model.isConnected && !fixture.model.isSubmitting }
        await fixture.transport.setHoldEventResults(true)
        let event: JSONValue = ["type": "waterfall", "event": "approval/request", "eventId": "permission", "agentId": "chat-1", "request": ["toolName": "web_search"]]
        await fixture.transport.emit("$events", event)
        try await waitUntil { fixture.model.approvals.count == 1 }
        fixture.model.answer(try XCTUnwrap(fixture.model.approvals.first), outcome: .allowedOnce)
        try await waitUntil { await fixture.transport.count("$events/result") == 1 }
        await fixture.transport.emit("$events", ["type": "ready", "clientId": "replacement-client"])
        await fixture.transport.emit("$events", event)
        try await waitUntil { fixture.model.approvals.first?.clientID == "replacement-client" }
        await fixture.transport.finishEventResults()
        try await waitUntil { !fixture.model.isAnswering }
        XCTAssertEqual(fixture.model.approvals.first?.clientID, "replacement-client")
    }

    private func makeFixture() -> (model: ChatModel, transport: ChatTestTransport, connection: ChatTestConnection, defaults: UserDefaults) {
        let defaults = UserDefaults(suiteName: "DSHChatTests.\(UUID().uuidString)")!
        let transport = ChatTestTransport()
        let connection = ChatTestConnection(transport: transport)
        return (ChatModel(connection: connection, defaults: defaults), transport, connection, defaults)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !(await condition()) {
            if Date() > limit { XCTFail("Timed out waiting for chat state"); throw TestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    nonisolated fileprivate static func event(_ type: String, seq: Int, data: JSONValue) -> JSONValue {
        ["type": "event", "event": ["type": .string(type), "seq": .number(Double(seq)), "time": 1_700_000_000_000, "data": data]]
    }

    private enum TestError: Error { case timeout }
}

private struct ChatTestConnection: DSHConnecting {
    let transport: ChatTestTransport
    func connected() async throws -> DSHConnectedClient {
        .init(client: DSHClient(transport: transport), identity: "http://localhost:2222")
    }
    func disconnect() async {}
}

private actor ChatTestTransport: DSHTransport {
    struct Call: Sendable { let endpoint: String; let args: RemoteArgs }
    private var calls: [Call] = []
    private var streams: [String: [AsyncThrowingStream<JSONValue, any Error>.Continuation]] = [:]
    private var sequence = 0
    private var catalog: JSONValue = ["groups": []]
    private var failModelSelection = false
    private var echoPrompts = true
    private var snapshot: JSONValue = ["type": "snapshot", "header": [:], "cursor": -1, "records": [], "hasMore": false, "projections": [:]]
    private var failEventsOnFollow = false
    private var holdEventResults = false
    private var pendingEventResults: [CheckedContinuation<Void, Never>] = []

    func call(_ endpoint: String, args: RemoteArgs) async throws -> JSONValue? {
        calls.append(.init(endpoint: endpoint, args: args))
        switch endpoint {
        case "session/modelCatalog": return catalog
        case "session/create": return ["sessionId": "chat-1"]
        case "session/selectModel":
            if failModelSelection { failModelSelection = false; throw RemoteErrorPayload(message: "Selection unavailable") }
            return .object([:])
        case "session/prompt":
            guard echoPrompts else { return .object([:]) }
            sequence += 1
            emit("session/follow", ChatModelTests.event("user/message", seq: sequence,
                data: ["source": ["kind": "user"], "content": args["request"]?["content"] ?? []]))
            sequence += 1
            emit("session/follow", ChatModelTests.event("turn/start", seq: sequence, data: ["turn": 1]))
            return .object([:])
        case "$events/result":
            if holdEventResults {
                await withCheckedContinuation { pendingEventResults.append($0) }
            }
            return .object([:])
        default: return .object([:])
        }
    }

    func stream(_ endpoint: String, args: RemoteArgs) async throws -> AsyncThrowingStream<JSONValue, any Error> {
        let (stream, continuation) = AsyncThrowingStream<JSONValue, any Error>.makeStream()
        streams[endpoint, default: []].append(continuation)
        if endpoint == "$events" { continuation.yield(["type": "ready", "clientId": "first-generation"]) }
        else if endpoint == "session/follow" {
            if failEventsOnFollow {
                failEventsOnFollow = false
                failStreams("$events")
                let baseline = snapshot
                Task {
                    try? await Task.sleep(for: .milliseconds(30))
                    continuation.yield(baseline)
                }
            } else { continuation.yield(snapshot) }
        }
        return stream
    }

    func emit(_ endpoint: String, _ value: JSONValue) {
        if let seq = value["event"]?["seq"]?.intValue { sequence = max(sequence, seq) }
        streams[endpoint]?.forEach { $0.yield(value) }
    }
    func count(_ endpoint: String) -> Int { calls.filter { $0.endpoint == endpoint }.count }
    func streamCount(_ endpoint: String) -> Int { streams[endpoint]?.count ?? 0 }
    func lastCall(_ endpoint: String) -> Call? { calls.last { $0.endpoint == endpoint } }
    func setCatalog(_ value: JSONValue) { catalog = value }
    func failNextModelSelection() { failModelSelection = true }
    func setEchoPrompts(_ value: Bool) { echoPrompts = value }
    func setSnapshot(_ value: JSONValue) { snapshot = value }
    func failEventsBeforeNextFollow() { failEventsOnFollow = true }
    func setHoldEventResults(_ value: Bool) { holdEventResults = value }
    func finishEventResults() {
        holdEventResults = false
        let pending = pendingEventResults
        pendingEventResults.removeAll()
        pending.forEach { $0.resume() }
    }
    func failStreams(_ endpoint: String) {
        streams.removeValue(forKey: endpoint)?.forEach { $0.finish(throwing: RemoteErrorPayload(message: "Disconnected")) }
    }
}
