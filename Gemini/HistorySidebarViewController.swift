import UIKit

public final class HistorySidebarViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    public var onSelectThread: ((ChatThreadSummary) -> Void)?
    public var onNewChatTapped: (() -> Void)?
    public var onLogoutTapped: (() -> Void)?

    private let client: GeminiRPCClient
    private var threads: [ChatThreadSummary] = []

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.dataSource = self
        tv.delegate = self
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let refreshControl = UIRefreshControl()

    public init(client: GeminiRPCClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        setupHeaderAndFooter()
        loadHistory()
    }

    private func setupHeaderAndFooter() {
        let newChatButton = UIButton(type: .system)
        newChatButton.setTitle("  Новый чат", for: .normal)
        let pencilConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        newChatButton.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: pencilConfig), for: .normal)
        newChatButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        newChatButton.tintColor = .white
        newChatButton.backgroundColor = .systemBlue
        newChatButton.layer.cornerRadius = 12
        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.addTarget(self, action: #selector(handleNewChat), for: .touchUpInside)

        let logoutButton = UIButton(type: .system)
        logoutButton.setTitle("Выйти из аккаунта", for: .normal)
        logoutButton.setTitleColor(.systemRed, for: .normal)
        logoutButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.addTarget(self, action: #selector(handleLogout), for: .touchUpInside)

        view.addSubview(newChatButton)
        view.addSubview(tableView)
        view.addSubview(logoutButton)

        refreshControl.addTarget(self, action: #selector(loadHistory), for: .valueChanged)
        tableView.addSubview(refreshControl)

        NSLayoutConstraint.activate([
            newChatButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            newChatButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            newChatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            newChatButton.heightAnchor.constraint(equalToConstant: 40),

            tableView.topAnchor.constraint(equalTo: newChatButton.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: logoutButton.topAnchor, constant: -8),

            logoutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            logoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            logoutButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc private func handleNewChat() {
        onNewChatTapped?()
    }

    @objc private func handleLogout() {
        onLogoutTapped?()
    }

    @objc public func loadHistory() {
        Task { @MainActor in
            do {
                self.threads = try await client.fetchChatHistory(limit: 30)
                self.tableView.reloadData()
            } catch {
                print("[Sidebar] Не удалось загрузить историю: \(error.localizedDescription)")
            }
            self.refreshControl.endRefreshing()
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return threads.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        let thread = threads[indexPath.row]
        cell.textLabel?.text = thread.title
        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        cell.textLabel?.textColor = .label
        cell.textLabel?.numberOfLines = 1

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        cell.detailTextLabel?.text = formatter.string(from: thread.updatedAt)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let thread = threads[indexPath.row]
        onSelectThread?(thread)
    }
}
