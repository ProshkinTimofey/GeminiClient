import Foundation

// MARK: - 1. Модели данных

public struct ConversationContext: Codable, Sendable, Equatable {
    public let conversationId: String
    public let responseId: String
    public let choiceId: String

    public init(conversationId: String = "", responseId: String = "", choiceId: String = "") {
        self.conversationId = conversationId
        self.responseId = responseId
        self.choiceId = choiceId
    }

    public static let empty = ConversationContext()
    
    public var isValid: Bool {
        return !conversationId.isEmpty && !responseId.isEmpty
    }
}

public struct ChatThreadSummary: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let updatedAt: Date

    public init(id: String, title: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let isUser: Bool
    public let timestamp: Date

    public init(id: String = UUID().uuidString, text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

public enum GeminiRPCError: LocalizedError, Sendable {
    case sessionExpired
    case handshakeFailed(String)
    case invalidResponse(statusCode: Int)
    case payloadEncodingFailed
    case parsingFailed(String)
    case emptyReply
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Сессия Google истекла. Требуется повторный вход в аккаунт."
        case .handshakeFailed(let reason):
            return "Ошибка рукопожатия с Gemini: \(reason)"
        case .invalidResponse(let statusCode):
            return "Неверный HTTP-ответ сервера (код: \(statusCode))."
        case .payloadEncodingFailed:
            return "Не удалось сформировать RPC-пакет batchexecute."
        case .parsingFailed(let details):
            return "Ошибка разбора ответа Google: \(details)"
        case .emptyReply:
            return "Gemini вернул пустой ответ."
        case .networkError(let details):
            return "Сетевая ошибка: \(details)"
        }
    }
}

// MARK: - 2. Безопасное извлечение по индексам

public extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 3. Высокопроизводительный парсер ответов Google

public struct BardResponseParser: Sendable {
    
    public static func extractPayloads(from responseString: String) throws -> [[Any]] {
        var cleanString = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanString.hasPrefix(")]}'") {
            cleanString = String(cleanString.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var results: [[Any]] = []
        let lines = cleanString.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { continue }
            
            guard let data = trimmed.data(using: .utf8),
                  let outerArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
                continue
            }

            for item in outerArray {
                guard let block = item as? [Any],
                      let tag = block[safe: 0] as? String, tag == "wrb.fr",
                      let jsonString = block[safe: 2] as? String,
                      let innerData = jsonString.data(using: .utf8),
                      let innerArray = try? JSONSerialization.jsonObject(with: innerData) as? [Any] else {
                    continue
                }
                results.append(innerArray)
            }
        }

        return results
    }

    public static func parseGenerateResponse(from responseString: String) throws -> (reply: String, newContext: ConversationContext) {
        let payloads = try extractPayloads(from: responseString)
        
        for payload in payloads {
            let metaBlock = payload[safe: 1] as? [Any]
            let convId = (metaBlock?[safe: 0] as? String) ?? ""
            let respId = (metaBlock?[safe: 1] as? String) ?? ""

            guard let candidates = payload[safe: 4] as? [Any],
                  let firstCandidate = candidates[safe: 0] as? [Any] else {
                continue
            }

            let choiceId = (firstCandidate[safe: 0] as? String) ?? ""
            
            if let textParts = firstCandidate[safe: 1] as? [Any],
               let text = textParts[safe: 0] as? String, !text.isEmpty {
                let context = ConversationContext(conversationId: convId, responseId: respId, choiceId: choiceId)
                return (reply: text, newContext: context)
            }
        }

        throw GeminiRPCError.emptyReply
    }

    public static func parseChatHistory(from responseString: String) throws -> [ChatThreadSummary] {
        let payloads = try extractPayloads(from: responseString)
        var threads: [ChatThreadSummary] = []

        for payload in payloads {
            guard let threadList = payload[safe: 0] as? [Any] else { continue }

            for item in threadList {
                guard let threadData = item as? [Any],
                      let id = threadData[safe: 0] as? String,
                      let title = threadData[safe: 1] as? String else {
                    continue
                }

                var date = Date()
                if let rawTime = threadData[safe: 2] as? Double {
                    date = Date(timeIntervalSince1970: rawTime > 10_000_000_000 ? rawTime / 1000.0 : rawTime)
                }

                threads.append(ChatThreadSummary(id: id, title: title, updatedAt: date))
            }
        }

        return threads
    }

    public static func parseThreadDetails(from responseString: String) throws -> ([ChatMessage], ConversationContext) {
        let payloads = try extractPayloads(from: responseString)
        var messages: [ChatMessage] = []
        var context = ConversationContext.empty

        for payload in payloads {
            let metaBlock = payload[safe: 1] as? [Any]
            let convId = (metaBlock?[safe: 0] as? String) ?? ""
            let respId = (metaBlock?[safe: 1] as? String) ?? ""
            context = ConversationContext(conversationId: convId, responseId: respId, choiceId: "")

            guard let turns = payload[safe: 0] as? [Any] else { continue }

            for turn in turns {
                guard let turnArray = turn as? [Any] else { continue }

                if let userQueryBlock = turnArray[safe: 0] as? [Any],
                   let userText = userQueryBlock[safe: 0] as? String {
                    messages.append(ChatMessage(text: userText, isUser: true))
                }

                if let modelResponses = turnArray[safe: 1] as? [Any],
                   let firstModelResp = modelResponses[safe: 0] as? [Any],
                   let textBlock = firstModelResp[safe: 1] as? [Any],
                   let modelText = textBlock[safe: 0] as? String {
                    messages.append(ChatMessage(text: modelText, isUser: false))
                }
            }
        }

        return (messages, context)
    }
}

// MARK: - 4. Клиент сетевых запросов GeminiRPCClient

public actor GeminiRPCClient {
    
    private let customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6.6 Mobile/15E148 Safari/604.1"
    
    private let appURL = URL(string: "https://gemini.google.com/app")!
    private let batchExecuteURL = URL(string: "https://gemini.google.com/_/BardChatUi/data/batchexecute")!
    private let streamGenerateURL = URL(string: "https://gemini.google.com/_/BardChatUi/data/assistant.lamda.BardFrontendService/StreamGenerate")!

    private let authStore: KeychainAuthStore
    private let session: URLSession

    private var snlm0eToken: String?
    private var blVersion: String = "boq_assistant-bard-web-server_20240319.08_p0"
    private var reqIdCounter: Int = 100000

    public init(authStore: KeychainAuthStore = .shared) {
        self.authStore = authStore
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        
        try? authStore.applyCookies(to: config)

        self.session = URLSession(configuration: config)
    }

    public func warmupSession() async throws {
        if snlm0eToken == nil {
            if let creds = try? authStore.load(), let token = creds.snlm0eToken {
                self.snlm0eToken = token
            }
        }

        var request = URLRequest(url: appURL)
        request.httpMethod = "GET"
        applyDefaultHeaders(to: &request)

        let (data, response) = try await execute(request)

        if let finalURL = response.url, finalURL.host?.contains("accounts.google.com") == true {
            throw GeminiRPCError.sessionExpired
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw GeminiRPCError.handshakeFailed("Не удалось декодировать ответ HTML.")
        }

        if let token = extractRegex(pattern: "\"SNlM0e\":\"([^\"]+)\"", from: html) {
            self.snlm0eToken = token
            if var creds = try? authStore.load() {
                creds = GeminiAuthCredentials(cookies: creds.cookies, snlm0eToken: token, createdAt: creds.createdAt)
                try? authStore.save(creds)
            }
        }

        if let bl = extractRegex(pattern: "\"cfb2h\":\"([^\"]+)\"", from: html) {
            self.blVersion = bl
        }

        guard self.snlm0eToken != nil else {
            throw GeminiRPCError.sessionExpired
        }
    }

    public func fetchChatHistory(limit: Int = 30) async throws -> [ChatThreadSummary] {
        try await ensureHandshake()

        let payload: [Any] = [limit, 2, NSNull(), 1]
        let rawResponse = try await sendBatchExecute(rpcId: "MaZiqc", payload: payload)
        return try BardResponseParser.parseChatHistory(from: rawResponse)
    }

    public func loadThreadMessages(conversationId: String) async throws -> ([ChatMessage], ConversationContext) {
        try await ensureHandshake()

        let payload: [Any] = [conversationId, 25, NSNull(), 1]
        let rawResponse = try await sendBatchExecute(rpcId: "hNvQHb", payload: payload)
        return try BardResponseParser.parseThreadDetails(from: rawResponse)
    }

    public func sendMessage(_ prompt: String, context: ConversationContext? = nil) async throws -> (reply: String, newContext: ConversationContext) {
        try await ensureHandshake()
        
        let reqId = nextReqId()
        let currentContext = context ?? .empty

        let innerPayload: [Any?] = [
            [prompt, 0, nil, nil, nil, nil, 0],
            ["ru"],
            [currentContext.conversationId, currentContext.responseId, currentContext.choiceId],
            nil, nil, nil,
            [1],
            0,
            [],
            [],
            1
        ]

        guard let innerData = try? JSONSerialization.data(withJSONObject: innerPayload, options: []),
              let innerString = String(data: innerData, encoding: .utf8) else {
            throw GeminiRPCError.payloadEncodingFailed
        }

        let envelope: [Any?] = [nil, innerString]
        guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let fReqString = String(data: envelopeData, encoding: .utf8) else {
            throw GeminiRPCError.payloadEncodingFailed
        }

        var components = URLComponents(url: streamGenerateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "bl", value: blVersion),
            URLQueryItem(name: "_reqid", value: String(reqId)),
            URLQueryItem(name: "rt", value: "c")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        applyDefaultHeaders(to: &request)

        let bodyParameters: [String: String] = [
            "f.req": fReqString,
            "at": snlm0eToken ?? ""
        ]
        request.httpBody = encodeFormBody(bodyParameters)

        let (data, response) = try await execute(request)

        if response.statusCode == 401 || response.statusCode == 403 {
            throw GeminiRPCError.sessionExpired
        }

        guard response.statusCode == 200, let rawString = String(data: data, encoding: .utf8) else {
            throw GeminiRPCError.invalidResponse(statusCode: response.statusCode)
        }

        return try BardResponseParser.parseGenerateResponse(from: rawString)
    }

    // MARK: - Приватные хелперы

    private func ensureHandshake() async throws {
        if snlm0eToken == nil {
            try await warmupSession()
        }
    }

    private func sendBatchExecute(rpcId: String, payload: [Any]) async throws -> String {
        let reqId = nextReqId()

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let payloadJsonString = String(data: payloadData, encoding: .utf8) else {
            throw GeminiRPCError.payloadEncodingFailed
        }

        let callEnvelope: [[[Any?]]] = [
            [
                [rpcId, payloadJsonString, nil, "generic"]
            ]
        ]

        guard let envelopeData = try? JSONSerialization.data(withJSONObject: callEnvelope, options: []),
              let fReqString = String(data: envelopeData, encoding: .utf8) else {
            throw GeminiRPCError.payloadEncodingFailed
        }

        var components = URLComponents(url: batchExecuteURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "rpcids", value: rpcId),
            URLQueryItem(name: "bl", value: blVersion),
            URLQueryItem(name: "_reqid", value: String(reqId)),
            URLQueryItem(name: "rt", value: "c")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        applyDefaultHeaders(to: &request)

        let bodyParameters: [String: String] = [
            "f.req": fReqString,
            "at": snlm0eToken ?? ""
        ]
        request.httpBody = encodeFormBody(bodyParameters)

        let (data, response) = try await execute(request)

        if response.statusCode == 401 || response.statusCode == 403 {
            throw GeminiRPCError.sessionExpired
        }

        guard response.statusCode == 200, let rawString = String(data: data, encoding: .utf8) else {
            throw GeminiRPCError.invalidResponse(statusCode: response.statusCode)
        }

        return rawString
    }

    private func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, urlResponse) = try await session.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw GeminiRPCError.invalidResponse(statusCode: -1)
            }
            return (data, httpResponse)
        } catch let rpcError as GeminiRPCError {
            throw rpcError
        } catch {
            throw GeminiRPCError.networkError(error.localizedDescription)
        }
    }

    private func applyDefaultHeaders(to request: inout URLRequest) {
        request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://gemini.google.com", forHTTPHeaderField: "Origin")
        request.setValue("https://gemini.google.com/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Same-Domain")
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
    }

    private func nextReqId() -> Int {
        reqIdCounter += 100000
        return reqIdCounter
    }

    private func encodeFormBody(_ parameters: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let postDataString = parameters.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")

        return postDataString.data(using: .utf8) ?? Data()
    }

    private func extractRegex(pattern: String, from string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
}
