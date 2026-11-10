import UIKit

public final class HistorySidebarViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    public var onSelectThread: ((ChatThreadSummary) -> Void)?
    public var onNewChatTapped: (() -> Void)?
    public var onLogoutTapped: (() -> Void)?

    private let client: GeminiRPCClient
    private var allThreads: [ChatThreadSummary] = []
    private var displayedThreads: [ChatThreadSummary] = []

    private lazy var searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.searchBarStyle = .minimal
        sb.placeholder = "Поиск по чатам"
        sb.delegate = self
        sb.translatesAutoresizingMaskIntoConstraints = false
        sb.autocapitalizationType = .none
        return sb
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .clear
        tv.separatorStyle = .singleLine
        tv.separatorColor = UIColor.separator.withAlphaComponent(0.2)
        tv.dataSource = self
        tv.delegate = self
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "История загружается...\nПотяните вниз для обновления"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        setupUI()
        loadHistory()
    }

    private func setupUI() {
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
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(logoutButton)

        refreshControl.addTarget(self, action: #selector(loadHistory), for: .valueChanged)
        tableView.addSubview(refreshControl)

        NSLayoutConstraint.activate([
            newChatButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            newChatButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            newChatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            newChatButton.heightAnchor.constraint(equalToConstant: 40),

            searchBar.topAnchor.constraint(equalTo: newChatButton.bottomAnchor, constant: 6),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            searchBar.heightAnchor.constraint(equalToConstant: 38),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: logoutButton.topAnchor, constant: -8),

            emptyStateLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            logoutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            logoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            logoutButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc private func handleNewChat() {
        searchBar.resignFirstResponder()
        onNewChatTapped?()
    }

    @objc private func handleLogout() {
        onLogoutTapped?()
    }

    @objc public func loadHistory() {
        Task { @MainActor in
            do {
                self.allThreads = try await client.fetchChatHistory(limit: 50)
                self.filterThreads()
                self.emptyStateLabel.isHidden = !self.displayedThreads.isEmpty
                if self.displayedThreads.isEmpty {
                    self.emptyStateLabel.text = "Нет сохранённых диалогов\nПотяните вниз для обновления"
                }
            } catch {
                print("[Sidebar] Ошибка загрузки истории: \(error.localizedDescription)")
                self.emptyStateLabel.text = "Ошибка загрузки истории.\nПотяните для повтора."
                self.emptyStateLabel.isHidden = false
            }
            self.refreshControl.endRefreshing()
        }
    }

    private func filterThreads() {
        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            displayedThreads = allThreads
        } else {
            displayedThreads = allThreads.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        emptyStateLabel.isHidden = !displayedThreads.isEmpty
        tableView.reloadData()
    }

    // MARK: - UISearchBarDelegate

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filterThreads()
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - UITableViewDataSource & Delegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedThreads.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        let thread = displayedThreads[indexPath.row]
        cell.textLabel?.text = thread.title
        cell.textLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        cell.textLabel?.textColor = .label
        cell.textLabel?.numberOfLines = 1

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        cell.detailTextLabel?.text = formatter.string(from: thread.updatedAt)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchBar.resignFirstResponder()
        let thread = displayedThreads[indexPath.row]
        onSelectThread?(thread)
    }
}
