import UIKit

@MainActor
public final class AppCoordinator {

    private let window: UIWindow
    private let client: GeminiRPCClient
    private var drawerController: SlideOverDrawerController?
    private var chatVC: ChatViewController?

    public init(window: UIWindow) {
        self.window = window
        self.client = GeminiRPCClient()
    }

    public func start() {
        if (try? KeychainAuthStore.shared.load()) != nil {
            showMainChatUI()
            warmupBackgroundSession()
        } else {
            presentAuthFlow(animated: false)
        }
    }

    private func showMainChatUI() {
        let chat = ChatViewController(client: client)
        self.chatVC = chat

        let chatNav = UINavigationController(rootViewController: chat)
        let sidebar = HistorySidebarViewController(client: client)

        let drawer = SlideOverDrawerController(mainViewController: chatNav, sidebarViewController: sidebar)
        self.drawerController = drawer

        chat.onHamburgerTapped = { [weak drawer] in
            drawer?.toggleSidebar()
        }

        chat.onRequireReauthentication = { [weak self] in
            self?.presentAuthFlow(animated: true)
        }

        sidebar.onNewChatTapped = { [weak drawer, weak chat] in
            chat?.resetChat()
            drawer?.closeSidebar()
        }

        sidebar.onSelectThread = { [weak drawer, weak chat] thread in
            chat?.loadThread(conversationId: thread.id)
            drawer?.closeSidebar()
        }

        sidebar.onLogoutTapped = { [weak self] in
            try? KeychainAuthStore.shared.clear()
            self?.presentAuthFlow(animated: true)
        }

        window.rootViewController = drawer
        window.makeKeyAndVisible()
    }

    private func warmupBackgroundSession() {
        Task {
            do {
                try await client.warmupSession()
            } catch GeminiRPCError.sessionExpired {
                presentAuthFlow(animated: true)
            } catch {
                print("[Coordinator] Warmup warning: \(error.localizedDescription)")
            }
        }
    }

    private func presentAuthFlow(animated: Bool) {
        let presenter: UIViewController
        if let root = window.rootViewController {
            presenter = root
        } else {
            let fallback = UIViewController()
            window.rootViewController = fallback
            window.makeKeyAndVisible()
            presenter = fallback
        }

        Task {
            let session = GeminiAuthSession()
            do {
                _ = try await session.authenticate(presentingFrom: presenter)
                self.showMainChatUI()
                self.warmupBackgroundSession()
            } catch {
                print("[Coordinator] Авторизация прервана: \(error.localizedDescription)")
            }
        }
    }
}
