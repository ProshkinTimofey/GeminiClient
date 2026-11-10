import UIKit

public final class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    public var onHamburgerTapped: (() -> Void)?
    public var onRequireReauthentication: (() -> Void)?

    private let client: GeminiRPCClient
    private var messages: [ChatMessage] = []
    private var currentContext: ConversationContext = .empty
    private var isGenerating: Bool = false
    private var selectedModel: GeminiModel = .flash

    private var inputBarBottomConstraint: NSLayoutConstraint!

    private lazy var modelPickerButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        btn.setTitleColor(.label, for: .normal)
        btn.addTarget(self, action: #selector(handleModelPickerTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .systemBackground
        tv.separatorStyle = .none
        tv.keyboardDismissMode = .interactive
        tv.dataSource = self
        tv.delegate = self
        tv.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseID)
        tv.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseID)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var inputBar: GrowingInputBarView = {
        let bar = GrowingInputBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onSendMessage = { [weak self] prompt in
            self?.sendMessage(prompt)
        }
        return bar
    }()

    private let typingIndicatorLabel: UILabel = {
        let label = UILabel()
        label.text = "Gemini генерирует ответ..."
        label.font = .italicSystemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    public init(client: GeminiRPCClient) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupLayout()
        setupKeyboardObservers()

        let welcome = ChatMessage(text: "Привет! Я готов к работе. О чем побеседуем?", isUser: false)
        messages.append(welcome)
        tableView.reloadData()
    }

    private func updateModelButtonTitle() {
        modelPickerButton.setTitle("Gemini \(selectedModel.shortBadge) ▾", for: .normal)
        modelPickerButton.sizeToFit()
    }

    private func setupNavigationBar() {
        view.backgroundColor = .systemBackground

        updateModelButtonTitle()
        navigationItem.titleView = modelPickerButton

        let sidebarConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let sidebarImage = UIImage(systemName: "sidebar.left", withConfiguration: sidebarConfig)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: sidebarImage,
            style: .plain,
            target: self,
            action: #selector(handleHamburger)
        )

        let newChatConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let newChatImage = UIImage(systemName: "square.and.pencil", withConfiguration: newChatConfig)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: newChatImage,
            style: .plain,
            target: self,
            action: #selector(handleNewChatTapped)
        )
    }

    @objc private func handleNewChatTapped() {
        resetChat()
    }

    @objc private func handleModelPickerTapped() {
        let alert = UIAlertController(title: "Модель Gemini", message: "Выберите модель для общения", preferredStyle: .actionSheet)
        
        for model in GeminiModel.allCases {
            let isCurrent = model == selectedModel
            let title = "\(isCurrent ? "✓ " : "")\(model.title)"
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                self.selectedModel = model
                self.updateModelButtonTitle()
                Task {
                    await self.client.setModel(model)
                }
            }))
        }
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = modelPickerButton
            popover.sourceRect = modelPickerButton.bounds
        }

        present(alert, animated: true)
    }

    @objc private func handleHamburger() {
        onHamburgerTapped?()
    }

    private func setupLayout() {
        view.addSubview(tableView)
        view.addSubview(typingIndicatorLabel)
        view.addSubview(inputBar)

        inputBarBottomConstraint = inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: typingIndicatorLabel.topAnchor),

            typingIndicatorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            typingIndicatorLabel.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -4),
            typingIndicatorLabel.heightAnchor.constraint(equalToConstant: 16),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottomConstraint
        ])
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else {
            return
        }

        let isHiding = endFrame.minY >= UIScreen.main.bounds.height
        inputBarBottomConstraint.constant = isHiding ? 0 : -endFrame.height

        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }

        if !isHiding {
            scrollToBottom(animated: true)
        }
    }

    private func sendMessage(_ prompt: String) {
        guard !isGenerating else { return }

        let userMessage = ChatMessage(text: prompt, isUser: true)
        messages.append(userMessage)
        tableView.reloadData()
        scrollToBottom(animated: true)

        setGeneratingState(true)

        Task { @MainActor in
            do {
                let response = try await client.sendMessage(prompt, context: currentContext)
                self.currentContext = response.newContext

                let aiMessage = ChatMessage(text: response.reply, isUser: false)
                self.messages.append(aiMessage)
                self.tableView.reloadData()
                self.scrollToBottom(animated: true)
                self.setGeneratingState(false)

            } catch GeminiRPCError.sessionExpired {
                self.setGeneratingState(false)
                self.onRequireReauthentication?()
            } catch {
                self.setGeneratingState(false)
                let errorMsg = ChatMessage(text: "⚠️ Ошибка: \(error.localizedDescription)", isUser: false)
                self.messages.append(errorMsg)
                self.tableView.reloadData()
                self.scrollToBottom(animated: true)
            }
        }
    }

    private func setGeneratingState(_ isGenerating: Bool) {
        self.isGenerating = isGenerating
        typingIndicatorLabel.isHidden = !isGenerating
        inputBar.setGenerating(isGenerating)
    }

    public func resetChat() {
        currentContext = .empty
        messages.removeAll()
        messages.append(ChatMessage(text: "Новый чат начат. Задайте любой вопрос!", isUser: false))
        tableView.reloadData()
    }

    public func loadThread(conversationId: String) {
        setGeneratingState(true)
        Task { @MainActor in
            do {
                let (threadMessages, context) = try await client.loadThreadMessages(conversationId: conversationId)
                self.messages = threadMessages
                self.currentContext = context
                self.tableView.reloadData()
                self.scrollToBottom(animated: false)
                self.setGeneratingState(false)
            } catch GeminiRPCError.sessionExpired {
                self.setGeneratingState(false)
                self.onRequireReauthentication?()
            } catch {
                self.setGeneratingState(false)
                print("[Chat] Ошибка загрузки ветки: \(error.localizedDescription)")
            }
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let lastIndex = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: lastIndex, at: .bottom, animated: animated)
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        if message.isUser {
            let cell = tableView.dequeueReusableCell(withIdentifier: UserMessageCell.reuseID, for: indexPath) as! UserMessageCell
            cell.configure(with: message)
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: AssistantMessageCell.reuseID, for: indexPath) as! AssistantMessageCell
            cell.configure(with: message)
            return cell
        }
    }
}
