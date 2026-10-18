import Combine
import DSHKit
import DSHProtocol
import DSHSession
import Foundation

/// One quick-chat surface, using DSH's authenticated local connection and
/// server-owned sessions. No workspace registration or folder selection occurs.
@MainActor
final class ChatModel: ObservableObject {
    @Published var draft = ""
    @Published var webSearchEnabled = true
    @Published private(set) var timeline = Timeline()
    @Published private(set) var pendingPrompt: String?
    @Published private(set) var approvals: [ChatApproval] = []
    @Published private(set) var questions: [ChatQuestionRequest] = []
    @Published private(set) var history: [ChatSummary]
    @Published private(set) var selectedSessionID: String?
    @Published private(set) var modelOptions: [ChatModelOption] = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var isStopping = false
    @Published private(set) var isAnswering = false
    @Published private(set) var awaitingResponse = false
    @Published private var unsupportedQuestionIDs: Set<String> = []

    private let connection: any DSHConnecting
    private let defaults: UserDefaults
    private static let historyKey = "DSHChat.history.v1"
    private var client: DSHClient?
    private var hostIdentity: String?
    private var sessionHostIdentity: String?
    private var eventsClientID: String?
    private var generation = UUID()
    private var pendingWirePrompt: String?
    private var pendingPromptAccepted = false
    private var sessionModelID: String?
    private var pendingThroughSeq = -1
    private var actionTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?

    init(connection: any DSHConnecting = DSHConnection(), defaults: UserDefaults = .standard) {
        self.connection = connection
        self.defaults = defaults
        history = defaults.data(forKey: Self.historyKey)
            .flatMap { try? JSONDecoder().decode([ChatSummary].self, from: $0) } ?? []
        history.sort { $0.updatedAt > $1.updatedAt }
    }

    var isBusy: Bool {
        isConnecting || isSubmitting || isStopping || isAnswering || awaitingResponse
            || timeline.running || timeline.live != nil || pendingPrompt != nil
            || !approvals.isEmpty || !questions.isEmpty || hasUnsupportedQuestions
    }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy }
    var canStartNewChat: Bool { !isBusy }
    var modelName: String { modelOptions.first { $0.id == selectedModelID }?.name ?? "DSH default" }
    var currentTitle: String {
        selectedSessionID.flatMap { id in history.first { $0.id == id && $0.hostIdentity == sessionHostIdentity }?.title }
            ?? "New Chat"
    }
    var connectionLabel: String {
        if isConnecting { return "Connecting…" }
        if !approvals.isEmpty || !questions.isEmpty || hasUnsupportedQuestions { return "Waiting for you" }
        if isStopping { return "Stopping…" }
        if isBusy { return isSearching ? "Searching the web…" : "Thinking…" }
        return isConnected ? "Connected to DSH" : "DSH local host"
    }
    var status: String { connectionLabel }
    var isSearching: Bool {
        timeline.items.contains { item in
            guard case .tool(let tool) = item.content else { return false }
            return tool.isRunning && [.webSearch, .webFetch].contains(ToolActivity(toolName: tool.name))
        }
    }
    var hasUnsupportedQuestions: Bool { !unsupportedQuestionIDs.isEmpty }
    var canStop: Bool {
        !isStopping && !isConnecting && selectedSessionID != nil
            && (timeline.running || timeline.live != nil || awaitingResponse
                || !approvals.isEmpty || !questions.isEmpty || hasUnsupportedQuestions)
    }

    func cleanedUserText(_ text: String) -> String { QuickChatPrompt.cleaned(text) }

    func send() {
        guard canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = webSearchEnabled
        draft = ""
        pendingPrompt = question
        pendingPromptAccepted = false
        errorMessage = nil
        isSubmitting = true
        actionTask = Task { [weak self] in
            guard let self else { return }
            var promptAttempted = false
            defer { self.isSubmitting = false; self.actionTask = nil }
            do {
                if !self.isConnected { try await self.connect(createSession: true) }
                if self.selectedSessionID == nil || self.followTask == nil { try await self.prepareSession() }
                try Task.checkCancellation()
                guard let client = self.client, let sessionID = self.selectedSessionID else { throw ChatError.streamEnded }
                try await self.ensureSessionModel(epoch: self.generation)
                let wire = QuickChatPrompt.text(question: question, webSearch: search, firstTurn: self.timeline.userTexts.isEmpty)
                self.pendingWirePrompt = wire
                self.pendingThroughSeq = self.timeline.cursor
                self.awaitingResponse = true
                promptAttempted = true
                try await client.prompt(sessionId: sessionID, content: [.text(wire)])
                self.pendingPromptAccepted = self.pendingPrompt != nil
                self.touchHistory(question: question)
                self.reconcilePendingPrompt()
            } catch is CancellationError {
                // A subscription can fail while its baseline is being opened.
                // No RPC was attempted, so preserve the question as an unsent
                // draft instead of leaving an optimistic bubble busy forever.
                if !promptAttempted { self.restoreUnsentQuestion(question) }
            } catch {
                self.restoreUnsentQuestion(question)
                self.errorMessage = Self.message(for: error)
            }
        }
    }

    /// Reads the model catalog without creating a host session until Send.
    func reconnect() {
        guard !isConnecting, !isSubmitting, !isAnswering, !isStopping else { return }
        errorMessage = nil
        actionTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.connect(createSession: false) }
            catch is CancellationError {}
            catch { self.errorMessage = Self.message(for: error) }
            self.actionTask = nil
        }
    }

    private func connect(createSession: Bool) async throws {
        isConnecting = true
        defer { isConnecting = false }
        endObservation()
        let epoch = generation
        do {
            await connection.disconnect() // Re-read rotated local handoff credentials.
            try Task.checkCancellation()
            let connected = try await connection.connected()
            try ensureGeneration(epoch)
            if let expected = sessionHostIdentity, expected != connected.identity {
                throw ChatError.hostChanged
            }
            hostIdentity = connected.identity
            client = connected.client
            let catalog = try await connected.client.modelCatalog()
            try ensureGeneration(epoch)
            modelOptions = catalog.groups.flatMap { group in
                group.models.map { model in
                    ChatModelOption(provider: group.id, model: model.id, name: model.name,
                                    reasoningEffort: model.reasoning?.defaultEffort)
                }
            }
            if selectedModelID == nil, let selection = catalog.default {
                selectedModelID = "\(selection.provider)/\(selection.model)"
            }
            if createSession && selectedSessionID == nil { try await createHostSession(epoch: epoch) }
            try await observeEvents(client: connected.client, epoch: epoch)
            if let sessionID = selectedSessionID { try await observeSession(client: connected.client, id: sessionID, epoch: epoch) }
            try ensureGeneration(epoch)
            isConnected = true
        } catch {
            if generation == epoch { endObservation(); await connection.disconnect() }
            throw error
        }
    }

    private func prepareSession() async throws {
        let epoch = generation
        if selectedSessionID == nil { try await createHostSession(epoch: epoch) }
        guard let client, let id = selectedSessionID else { throw ChatError.streamEnded }
        if followTask == nil { try await observeSession(client: client, id: id, epoch: epoch) }
    }

    private func createHostSession(epoch: UUID) async throws {
        guard let client, let hostIdentity else { throw ChatError.streamEnded }
        let id = try await client.createSession() // No cwd or workspace binding.
        try ensureGeneration(epoch)
        selectedSessionID = id
        sessionHostIdentity = hostIdentity
        sessionModelID = nil
        history.insert(.init(id: id, title: "New Chat", updatedAt: Date(), hostIdentity: hostIdentity, modelID: nil), at: 0)
        saveHistory()
    }

    private func ensureSessionModel(epoch: UUID) async throws {
        guard selectedModelID != sessionModelID, let client, let id = selectedSessionID,
              let option = modelOptions.first(where: { $0.id == selectedModelID }) else { return }
        try await client.selectModel(sessionId: id, provider: option.provider, model: option.model, reasoningEffort: option.reasoningEffort)
        try ensureGeneration(epoch)
        sessionModelID = option.id
        touchHistory()
    }

    private func observeSession(client: DSHClient, id: String, epoch: UUID) async throws {
        var iterator = try await client.follow(sessionId: id, maxMessages: 100).makeAsyncIterator()
        guard let baseline = try await iterator.next() else { throw ChatError.streamEnded }
        try ensureGeneration(epoch)
        apply(baseline)
        followTask = Task { [weak self] in
            do {
                while let frame = try await iterator.next() {
                    try Task.checkCancellation()
                    guard let self, self.generation == epoch else { return }
                    self.apply(frame)
                }
                throw ChatError.streamEnded
            } catch is CancellationError {}
            catch { self?.streamFailed(error, epoch: epoch) }
        }
    }

    private func observeEvents(client: DSHClient, epoch: UUID) async throws {
        var iterator = try await client.events().makeAsyncIterator()
        while let frame = try await iterator.next() {
            try ensureGeneration(epoch)
            handle(frame, epoch: epoch)
            if eventsClientID != nil { break }
        }
        guard eventsClientID != nil else { throw ChatError.streamEnded }
        eventsTask = Task { [weak self] in
            do {
                while let frame = try await iterator.next() {
                    try Task.checkCancellation()
                    guard let self, self.generation == epoch else { return }
                    self.handle(frame, epoch: epoch)
                }
                throw ChatError.streamEnded
            } catch is CancellationError {}
            catch { self?.streamFailed(error, epoch: epoch) }
        }
    }

    private func apply(_ frame: SessionFollowFrame) {
        switch frame {
        case .snapshot(let snapshot):
            timeline.reset(with: snapshot)
            awaitingResponse = timeline.running || timeline.live != nil
            // A successful prompt RPC is never replayed. A fresh authoritative
            // snapshot may omit its old user record when history is truncated.
            if pendingPromptAccepted {
                pendingPrompt = nil
                pendingWirePrompt = nil
                pendingPromptAccepted = false
            }
        case .event(let event):
            let previousCursor = timeline.cursor
            timeline.apply(event)
            if event.seq > previousCursor, event.type == "turn/end" {
                awaitingResponse = false
                unsupportedQuestionIDs.removeAll()
            }
        case .assistantStream(let stream):
            if case .end(let attemptID, _) = stream,
               let live = timeline.live, live.attemptId == attemptID, !live.text.isEmpty {
                // Transport completion may precede the durable message. Keep
                // the last answer mounted until that message or turn/end
                // replaces it, instead of clearing it between deliveries.
                break
            }
            timeline.apply(stream)
        case .unknown: break
        }
        reconcilePendingPrompt()
        if let title = timeline.title, !title.isEmpty { touchHistory(title: title) }
    }

    private func reconcilePendingPrompt() {
        guard let wire = pendingWirePrompt, timeline.items.contains(where: { item in
            guard item.seq > pendingThroughSeq, case .user(let text, _) = item.content else { return false }
            return text == wire
        }) else { return }
        pendingPrompt = nil
        pendingWirePrompt = nil
        pendingPromptAccepted = false
    }

    private func handle(_ frame: RemoteEventFrame, epoch: UUID) {
        switch frame {
        case .ready(let id, _):
            eventsClientID = id.isEmpty ? nil : id
            approvals.removeAll()
            questions.removeAll()
            unsupportedQuestionIDs.removeAll()
        case .waterfall(let event, let id, let agentID, let request) where agentID == selectedSessionID:
            guard let eventsClientID else { return }
            if event == "approval/request" {
                approvals.removeAll { $0.id == id }
                approvals.append(.init(id: id, request: request, clientID: eventsClientID, generation: epoch))
            } else if event == "user-questions/request" {
                questions.removeAll { $0.id == id }
                let question = ChatQuestionRequest(id: id, request: request, clientID: eventsClientID, generation: epoch)
                guard !id.isEmpty, question.isValid else {
                    unsupportedQuestionIDs.insert(id)
                    errorMessage = "DSH sent a question this app could not display. Stop the response, then try again."
                    return
                }
                unsupportedQuestionIDs.remove(id)
                questions.append(question)
            }
        case .cancel(let id):
            approvals.removeAll { $0.id == id }
            questions.removeAll { $0.id == id }
            unsupportedQuestionIDs.remove(id)
        default: break
        }
    }

    func stop() {
        guard canStop, let client, let id = selectedSessionID else { return }
        isStopping = true
        errorMessage = nil
        stopTask = Task { [weak self] in
            do { try await client.cancel(sessionId: id) }
            catch { self?.errorMessage = Self.message(for: error) }
            self?.isStopping = false
            self?.stopTask = nil
        }
    }

    func newChat() {
        guard canStartNewChat else { return }
        actionTask?.cancel()
        endObservation()
        selectedSessionID = nil
        sessionHostIdentity = nil
        sessionModelID = nil
        timeline = Timeline()
        pendingPrompt = nil
        pendingWirePrompt = nil
        pendingPromptAccepted = false
        awaitingResponse = false
        errorMessage = nil
        draft = ""
    }

    func openChat(id: String) {
        guard canStartNewChat, let item = history.first(where: { $0.id == id }) else { return }
        endObservation()
        selectedSessionID = item.id
        sessionHostIdentity = item.hostIdentity
        selectedModelID = item.modelID
        sessionModelID = item.modelID
        timeline = Timeline()
        draft = ""
        reconnect()
    }

    /// Removes this app's history entry; DSH continues owning the host session.
    func deleteChat(id: String) {
        guard canStartNewChat else { return }
        if selectedSessionID == id { newChat() }
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func selectModel(id: String) {
        guard !isBusy, let option = modelOptions.first(where: { $0.id == id }) else { return }
        guard let sessionID = selectedSessionID, let client else { selectedModelID = id; return }
        isSubmitting = true
        let epoch = generation
        actionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSubmitting = false; self.actionTask = nil }
            do {
                try await client.selectModel(sessionId: sessionID, provider: option.provider, model: option.model, reasoningEffort: option.reasoningEffort)
                try self.ensureGeneration(epoch)
                self.selectedModelID = id
                self.sessionModelID = id
                self.touchHistory()
            } catch is CancellationError {}
            catch { self.errorMessage = Self.message(for: error) }
        }
    }

    func answer(_ approval: ChatApproval, outcome: ApprovalOutcome) {
        guard approvals.contains(where: { $0.id == approval.id }) else { return }
        resolve(id: approval.id, clientID: approval.clientID, epoch: approval.generation, value: .string(outcome.rawValue))
    }

    func answer(_ request: ChatQuestionRequest, answers: [String: String]) {
        answer(request, selections: [:], custom: answers)
    }

    func answer(_ request: ChatQuestionRequest, selections: [String: [String]], custom: [String: String]) {
        guard questions.contains(where: { $0.id == request.id }), request.isValid else { return }
        var answers: [JSONValue] = []
        for question in request.questions {
            let selected = selections[question.id] ?? []
            let text = (custom[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard (!selected.isEmpty || !text.isEmpty), question.multiSelect || selected.count <= 1,
                  selected.allSatisfy({ value in question.options.contains { $0.label == value } }) else {
                errorMessage = "Answer each question before continuing."
                return
            }
            var value: [String: JSONValue] = ["id": .string(question.id), "selected": .array(selected.map(JSONValue.string))]
            if !text.isEmpty { value["custom"] = .string(text) }
            answers.append(.object(value))
        }
        resolve(id: request.id, clientID: request.clientID, epoch: request.generation, value: ["answers": .array(answers)])
    }

    private func resolve(id: String, clientID: String, epoch: UUID, value: JSONValue) {
        guard !isAnswering, epoch == generation, clientID == eventsClientID, let client else { return }
        isAnswering = true
        errorMessage = nil
        answerTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isAnswering = false; self.answerTask = nil }
            do {
                try await client.resolveEvent(clientId: clientID, eventId: id, outcome: .result(value))
                try self.ensureGeneration(epoch)
                guard self.eventsClientID == clientID else { return }
                self.approvals.removeAll { $0.id == id }
                self.questions.removeAll { $0.id == id }
            } catch is CancellationError {}
            catch { self.errorMessage = Self.message(for: error) }
        }
    }

    func close() {
        actionTask?.cancel()
        stopTask?.cancel()
        answerTask?.cancel()
        endObservation()
        Task { await connection.disconnect() }
    }

    private func streamFailed(_ error: any Error, epoch: UUID) {
        guard epoch == generation else { return }
        endObservation()
        errorMessage = Self.message(for: error)
    }

    private func endObservation() {
        generation = UUID()
        followTask?.cancel()
        eventsTask?.cancel()
        followTask = nil
        eventsTask = nil
        eventsClientID = nil
        approvals.removeAll()
        questions.removeAll()
        unsupportedQuestionIDs.removeAll()
        isConnected = false
    }

    private func restoreUnsentQuestion(_ question: String) {
        awaitingResponse = false
        pendingPrompt = nil
        pendingWirePrompt = nil
        pendingPromptAccepted = false
        draft = draft.isEmpty ? question : question + "\n\n" + draft
    }

    private func ensureGeneration(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }

    private func touchHistory(question: String? = nil, title: String? = nil) {
        guard let id = selectedSessionID, let index = history.firstIndex(where: { $0.id == id && $0.hostIdentity == sessionHostIdentity }) else { return }
        let old = history[index]
        if let title { history[index].title = title }
        else if history[index].title == "New Chat", let question {
            history[index].title = String(question.replacingOccurrences(of: "\n", with: " ").prefix(72))
        }
        history[index].modelID = selectedModelID
        if question != nil { history[index].updatedAt = Date() }
        if history[index] != old { history.sort { $0.updatedAt > $1.updatedAt }; saveHistory() }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: Self.historyKey) }
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? ChatError { return error.localizedDescription }
        return DSHConnectionError.message(for: error)
    }

    private enum ChatError: LocalizedError {
        case streamEnded, hostChanged
        var errorDescription: String? {
            switch self {
            case .streamEnded: "The connection to DSH closed. Reconnect to resume this chat."
            case .hostChanged: "This chat belongs to another DSH host. Start a new chat to use the current host."
            }
        }
    }
}
