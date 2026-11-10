import Foundation
import UIKit
import WebKit
import Security

// MARK: - 1. Модели учетных данных и кук

/// Сериализуемая обертка над системным HTTPCookie для безопасного сохранения в Keychain.
public struct CodableCookie: Codable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expiresDate: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool

    public init(httpCookie: HTTPCookie) {
        self.name = httpCookie.name
        self.value = httpCookie.value
        self.domain = httpCookie.domain
        self.path = httpCookie.path
        self.expiresDate = httpCookie.expiresDate
        self.isSecure = httpCookie.isSecure
        self.isHTTPOnly = httpCookie.isHTTPOnly
    }

    /// Восстановление нативного HTTPCookie для передачи в URLSessionConfiguration.
    public func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expiresDate = expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = true
        }
        if isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = true
        }
        return HTTPCookie(properties: properties)
    }
}

/// Единая модель учетных данных сессии Google Gemini.
public struct GeminiAuthCredentials: Codable, Sendable {
    public let cookies: [CodableCookie]
    public let snlm0eToken: String?
    public let createdAt: Date

    public init(cookies: [CodableCookie], snlm0eToken: String?, createdAt: Date = Date()) {
        self.cookies = cookies
        self.snlm0eToken = snlm0eToken
        self.createdAt = createdAt
    }

    /// Преобразование всех сохраненных кук в массив нативных HTTPCookie.
    public var httpCookies: [HTTPCookie] {
        return cookies.compactMap { $0.toHTTPCookie() }
    }
}

// MARK: - 2. Ошибки модуля авторизации

public enum GeminiAuthError: LocalizedError, Sendable {
    case userCancelled
    case sessionAlreadyInProgress
    case missingRequiredCookies
    case keychainError(status: OSStatus)
    case credentialsNotFound
    case serializationFailed
    case webViewFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Авторизация отменена пользователем."
        case .sessionAlreadyInProgress:
            return "Процесс авторизации уже запущен."
        case .missingRequiredCookies:
            return "Не удалось перехватить обязательные сессионные куки Google."
        case .keychainError(let status):
            return "Ошибка системного Keychain (код статуса: \(status))."
        case .credentialsNotFound:
            return "Сохраненные учетные данные Gemini не найдены в Keychain."
        case .serializationFailed:
            return "Ошибка сериализации/десериализации данных сессии."
        case .webViewFailed(let error):
            return "Ошибка загрузки веб-интерфейса: \(error.localizedDescription)"
        }
    }
}

// MARK: - 3. Потокобезопасное хранилище KeychainAuthStore

public final class KeychainAuthStore: @unchecked Sendable {
    public static let shared = KeychainAuthStore()

    private let service: String = "com.google.gemini.session"
    private let account: String = "auth_credentials"
    private let lock = NSLock()

    private init() {}

    /// Сохранение учетных данных в защищенный Keychain с уровнем AccessibleAfterFirstUnlockThisDeviceOnly.
    public func save(_ credentials: GeminiAuthCredentials) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let encodedData = try? JSONEncoder().encode(credentials) else {
            throw GeminiAuthError.serializationFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = encodedData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GeminiAuthError.keychainError(status: status)
        }
    }

    /// Чтение сохраненных учетных данных.
    public func load() throws -> GeminiAuthCredentials {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw GeminiAuthError.credentialsNotFound
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw GeminiAuthError.keychainError(status: status)
        }

        guard let credentials = try? JSONDecoder().decode(GeminiAuthCredentials.self, from: data) else {
            throw GeminiAuthError.serializationFailed
        }

        return credentials
    }

    /// Полное удаление сессии из Keychain (Logout).
    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiAuthError.keychainError(status: status)
        }
    }

    /// Внедрение сохраненных кук в конфигурацию нативного URLSession.
    public func applyCookies(to sessionConfig: URLSessionConfiguration) throws {
        let credentials = try load()
        let cookieStorage = sessionConfig.httpCookieStorage ?? HTTPCookieStorage.shared
        sessionConfig.httpCookieStorage = cookieStorage

        for cookie in credentials.httpCookies {
            cookieStorage.setCookie(cookie)
        }
    }
}

// MARK: - 4. Модуль авторизации GeminiAuthSession

@MainActor
public final class GeminiAuthSession: NSObject {
    
    private let customSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6.6 Mobile/15E148 Safari/604.1"
    private let targetURL = URL(string: "https://accounts.google.com/ServiceLogin?service=bard&continue=https%3A%2F%2Fgemini.google.com%2Fapp")!

    private let requiredCookieNames: Set<String> = [
        "SID", "HSID", "SSID", "__Secure-1PSID", "__Secure-3PSID"
    ]

    private var webView: WKWebView?
    private weak var cookieStore: WKHTTPCookieStore?
    private var navigationController: UINavigationController?

    private var continuation: CheckedContinuation<GeminiAuthCredentials, Error>?
    private var isCompleted: Bool = false

    private let keychainStore: KeychainAuthStore

    public init(keychainStore: KeychainAuthStore = .shared) {
        self.keychainStore = keychainStore
        super.init()
    }

    deinit {
        print("[Memory] GeminiAuthSession deallocated cleanly")
    }

    public func authenticate(presentingFrom parentVC: UIViewController) async throws -> GeminiAuthCredentials {
        guard continuation == nil, !isCompleted else {
            throw GeminiAuthError.sessionAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.startAuthFlow(presentingFrom: parentVC)
        }
    }

    private func startAuthFlow(presentingFrom parentVC: UIViewController) {
        let configuration = WKWebViewConfiguration()
        let nonPersistentStore = WKWebsiteDataStore.nonPersistent()
        configuration.websiteDataStore = nonPersistentStore
        configuration.suppressesIncrementalRendering = false
        configuration.allowsInlineMediaPlayback = true

        let userContentController = WKUserContentController()
        let overlayFixScript = """
        (function() {
            function removeOverlays() {
                var selectors = [
                    '[role="dialog"]',
                    '.cdk-overlay-backdrop',
                    '.cdk-overlay-container',
                    '.glue-cookie-notification-bar',
                    '.modal-backdrop',
                    'div[style*="z-index: 2147483647"]',
                    'div[style*="z-index: 1000"]'
                ];
                selectors.forEach(function(sel) {
                    document.querySelectorAll(sel).forEach(function(el) {
                        el.style.pointerEvents = 'none';
                        el.style.display = 'none';
                    });
                });
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
            }
            window.addEventListener('DOMContentLoaded', removeOverlays);
            setInterval(removeOverlays, 800);
        })();
        """
        let userScript = WKUserScript(source: overlayFixScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = customSafariUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        let store = nonPersistentStore.httpCookieStore
        self.cookieStore = store
        store.add(self)

        let hostVC = UIViewController()
        hostVC.title = "Вход в Google"
        hostVC.view.backgroundColor = UIColor(red: 19.0/255.0, green: 19.0/255.0, blue: 20.0/255.0, alpha: 1.0)
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        hostVC.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: hostVC.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: hostVC.view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: hostVC.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: hostVC.view.trailingAnchor)
        ])

        let cancelButton = UIBarButtonItem(
            title: "Отмена",
            style: .plain,
            target: self,
            action: #selector(handleCancelTapped)
        )
        hostVC.navigationItem.leftBarButtonItem = cancelButton

        let nav = UINavigationController(rootViewController: hostVC)
        nav.modalPresentationStyle = .fullScreen
        nav.isModalInPresentation = true
        self.navigationController = nav

        parentVC.present(nav, animated: true) { [weak self] in
            guard let self = self, let targetURL = self.webView?.url ?? Optional(self.targetURL) else { return }
            var request = URLRequest(url: targetURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            self.webView?.load(request)
        }
    }

    @objc private func handleCancelTapped() {
        finish(with: .failure(GeminiAuthError.userCancelled))
    }

    private func evaluateAuthState() {
        guard !isCompleted, let webView = self.webView, let currentURL = webView.url else { return }

        guard let host = currentURL.host?.lowercased(), host.contains("gemini.google.com") else {
            return
        }

        cookieStore?.getAllCookies { [weak self] allCookies in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isCompleted else { return }

                let googleCookies = allCookies.filter { $0.domain.contains("google.com") }
                let currentCookieNames = Set(googleCookies.map { $0.name })

                guard self.requiredCookieNames.isSubset(of: currentCookieNames) else {
                    return
                }

                let snlm0eToken = await self.extractSNlM0eToken()

                let codableCookies = googleCookies.map { CodableCookie(httpCookie: $0) }
                let credentials = GeminiAuthCredentials(
                    cookies: codableCookies,
                    snlm0eToken: snlm0eToken,
                    createdAt: Date()
                )

                do {
                    try self.keychainStore.save(credentials)
                    self.finish(with: .success(credentials))
                } catch {
                    self.finish(with: .failure(error))
                }
            }
        }
    }

    private func extractSNlM0eToken() async -> String? {
        guard let webView = self.webView else { return nil }
        let js = "window.WIZ_global_data?.SNlM0e || ''"
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let token = result as? String, !token.isEmpty {
                return token
            }
        } catch {}
        return nil
    }

    private func finish(with result: Result<GeminiAuthCredentials, Error>) {
        guard !isCompleted else { return }
        isCompleted = true

        destroyWebView()

        if let nav = self.navigationController, nav.presentingViewController != nil {
            nav.dismiss(animated: true) { [weak self] in
                self?.resumeContinuation(with: result)
            }
        } else {
            resumeContinuation(with: result)
        }
    }

    private func resumeContinuation(with result: Result<GeminiAuthCredentials, Error>) {
        guard let continuation = self.continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let credentials):
            continuation.resume(returning: credentials)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func destroyWebView() {
        if let store = self.cookieStore {
            store.remove(self)
            self.cookieStore = nil
        }

        guard let webView = self.webView else { return }

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        let userContentController = webView.configuration.userContentController
        userContentController.removeAllUserScripts()
        userContentController.removeAllScriptMessageHandlers()

        webView.loadHTMLString("", baseURL: nil)

        webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: {}
        )

        webView.removeFromSuperview()
        self.webView = nil
        self.navigationController = nil
    }
}

// MARK: - 5. Реализация делегатов WebKit

extension GeminiAuthSession: WKHTTPCookieStoreObserver {
    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        evaluateAuthState()
    }
}

extension GeminiAuthSession: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluateAuthState()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            finish(with: .failure(GeminiAuthError.webViewFailed(error)))
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            finish(with: .failure(GeminiAuthError.webViewFailed(error)))
        }
    }
}

extension GeminiAuthSession: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
