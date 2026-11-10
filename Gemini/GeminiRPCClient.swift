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

public enum GeminiModel: String, CaseIterable, Codable, Sendable {
    case flash = "gemini-2.0-flash"
    case pro = "gemini-2.0-pro"
    case flashLite = "gemini-2.0-flash-lite"

    public var title: String {
        switch self {
        case .flash: return "Gemini 2.5 Flash"
        case .pro: return "Gemini 2.5 Pro"
        case .flashLite: return "Flash-Lite"
        }
    }

    public var shortBadge: String {
        switch self {
        case .flash: return "Flash ⚡️"
        case .pro: return "Pro 🧠"
        case .flashLite: return "Lite 🚀"
        }
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
            return "Сессия Google Gemini истекла. Требуется повторный вход."
        case .handshakeFailed(let reason):
            return "Не удалось инициализировать сессию (Handshake): \(reason)"
        case .invalidResponse(let statusCode):
            return "Некорректный HTTP-ответ сервера Google: \(statusCode)"
        case .payloadEncodingFailed:
            return "Ошибка сериализации параметров запроса."
        case .parsingFailed(let details):
            return "Ошибка парсинга RPC-ответа: \(details)"
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
    
    /// Надежный извлекатель вложенных JSON-пейлоадов из формата Google (wrb.fr).
    /// Не разбивает строки по переносу строки `\n`, сохраняя многострочный код и форматирование целиком.
    public static func extractPayloads(from responseString: String) throws -> [[Any]] {
        var cleanString = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanString.hasPrefix(")]}'") {
            cleanString = String(cleanString.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var results: [[Any]] = []
        var searchIndex = cleanString.startIndex

        while searchIndex < cleanString.endIndex,
              let range = cleanString[searchIndex...].range(of: "[[\"wrb.fr\"") {
            let chunkStart = range.lowerBound
            var bracketCount = 0
            var inString = false
            var escape = false
            var chunkEnd = chunkStart
            
            var curr = chunkStart
            while curr < cleanString.endIndex {
                let char = cleanString[curr]
                if escape {
                    escape = false
                } else if char == "\\" {
                    escape = true
                } else if char == "\"" {
                    inString.toggle()
                } else if !inString {
                    if char == "[" {
                        bracketCount += 1
                    } else if char == "]" {
                        bracketCount -= 1
                        if bracketCount == 0 {
                            chunkEnd = cleanString.index(after: curr)
                            break
                        }
                    }
                }
                curr = cleanString.index(after: curr)
            }
            
            if bracketCount == 0 {
                let jsonSubstring = String(cleanString[chunkStart..<chunkEnd])
                if let data = jsonSubstring.data(using: .utf8),
                   let outerArray = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any] {
                    for item in outerArray {
                        if let block = item as? [Any],
                           let tag = block[safe: 0] as? String, tag == "wrb.fr",
                           let jsonString = block[safe: 2] as? String,
                           let innerData = jsonString.data(using: .utf8),
                           let innerArray = try? JSONSerialization.jsonObject(with: innerData, options: [.fragmentsAllowed]) as? [Any] {
                            results.append(innerArray)
                        }
                    }
                }
                searchIndex = chunkEnd
            } else {
                searchIndex = cleanString.index(after: chunkStart)
            }
        }
        
        // Резервный фолбэк для обычных JSON-ответов
        if results.isEmpty, let data = cleanString.data(using: .utf8),
           let directArray = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any] {
            results.append(directArray)
        }

        return results
    }

    /// Парсинг ответа генерации StreamGenerate.
    /// Перебирает все чанки с конца (в стриме финальный и полный ответ находится в самом последнем чанке),
    /// и объединяет все текстовые фрагменты кандидата, исключая обрезку до одного слова.
    public static func parseGenerateResponse(from responseString: String) throws -> (reply: String, newContext: ConversationContext) {
        let payloads = try extractPayloads(from: responseString)
        
        var bestReply: String = ""
        var bestContext = ConversationContext.empty

        for payload in payloads.reversed() {
            let metaBlock = payload[safe: 1] as? [Any]
            let convId = (metaBlock?[safe: 0] as? String) ?? ""
            let respId = (metaBlock?[safe: 1] as? String) ?? ""

            guard let candidates = payload[safe: 4] as? [Any],
                  let firstCandidate = candidates[safe: 0] as? [Any] else {
                continue
            }

            let choiceId = (firstCandidate[safe: 0] as? String) ?? ""
            
            var fullText = ""
            if let textParts = firstCandidate[safe: 1] as? [Any] {
                let parts = textParts.compactMap { part -> String? in
                    if let s = part as? String { return s }
                    if let arr = part as? [Any], let s = arr[safe: 0] as? String { return s }
                    return nil
                }
                fullText = parts.joined()
            }

            if !fullText.isEmpty && fullText.count > bestReply.count {
                bestReply = fullText
                bestContext = ConversationContext(conversationId: convId, responseId: respId, choiceId: choiceId)
            }
        }

        if !bestReply.isEmpty {
            return (reply: bestReply, newContext: bestContext)
        }

        throw GeminiRPCError.emptyReply
    }

    /// Парсинг истории чатов из RPC MaZiqc
    public static func parseChatHistory(from responseString: String) throws -> [ChatThreadSummary] {
        let payloads = try extractPayloads(from: responseString)
        var threads: [ChatThreadSummary] = []

        for payload in payloads {
            var candidateLists: [[Any]] = []
            if let first = payload[safe: 0] as? [Any], first[safe: 0] is [Any] {
                if let list = payload[safe: 0] as? [[Any]] {
                    candidateLists.append(contentsOf: list)
                }
            } else if payload[safe: 0] is [Any] {
                for item in payload {
                    if let threadData = item as? [Any] {
                        candidateLists.append(threadData)
                    }
                }
            }

            for threadData in candidateLists {
                guard let id = threadData[safe: 0] as? String,
                      let title = threadData[safe: 1] as? String else {
                    continue
                }

                var date = Date()
                if let rawTime = threadData[safe: 2] as? Double {
                    date = Date(timeIntervalSince1970: rawTime > 10_000_000_000 ? rawTime / 1000.0 : rawTime)
                } else if let rawTimeStr = threadData[safe: 2] as? String, let rawTime = Double(rawTimeStr) {
                    date = Date(timeIntervalSince1970: rawTime > 10_000_000_000 ? rawTime / 1000.0 : rawTime)
                }

                threads.append(ChatThreadSummary(id: id, title: title, updatedAt: date))
            }
        }

        return threads
    }

    /// Парсинг сообщений конкретного треда из RPC hNvQHb
    public static func parseThreadDetails(from responseString: String) throws -> ([ChatMessage], ConversationContext) {
        let payloads = try extractPayloads(from: responseString)
        var messages: [ChatMessage] = []
        var context = ConversationContext.empty

        for payload in payloads {
            let metaBlock = payload[safe: 1] as? [Any]
            let convId = (metaBlock?[safe: 0] as? String) ?? ""
            let respId = (metaBlock?[safe: 1] as? String) ?? ""
            if !convId.isEmpty {
                context = ConversationContext(conversationId: convId, responseId: respId, choiceId: "")
            }

            guard let turns = payload[safe: 0] as? [Any] else { continue }

            for turn in turns {
                guard let turnArray = turn as? [Any] else { continue }

                if let userQueryBlock = turnArray[safe: 0] as? [Any],
                   let userText = userQueryBlock[safe: 0] as? String {
                    messages.append(ChatMessage(text: userText, isUser: true))
                }

                if let modelResponses = turnArray[safe: 1] as? [Any],
                   let firstModelResp = modelResponses[safe: 0] as? [Any],
                   let textBlock = firstModelResp[safe: 1] as? [Any] {
                    let parts = textBlock.compactMap { part -> String? in
                        if let s = part as? String { return s }
                        if let arr = part as? [Any], let s = arr[safe: 0] as? String { return s }
                        return nil
                    }
                    let modelText = parts.joined()
                    if !modelText.isEmpty {
                        messages.append(ChatMessage(text: modelText, isUser: false))
                    }
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

    public var currentModel: GeminiModel = .flash

    public func setModel(_ model: GeminiModel) {
        self.currentModel = model
    }

    public init(authStore: KeychainAuthStore = .shared) {
        self.authStore = authStore
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45.0
        config.timeoutIntervalForResource = 90.0
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

    public func fetchChatHistory(limit: Int = 50) async throws -> [ChatThreadSummary] {
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
    }

    private func nextReqId() -> Int {
        reqIdCounter += 100000
        return reqIdCounter
    }

    private func encodeFormBody(_ parameters: [String: String]) -> Data {
        let parameterArray = parameters.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }
        return parameterArray.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private func extractRegex(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }
}
