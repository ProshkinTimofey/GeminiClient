import UIKit

// MARK: - Ячейка сообщения пользователя

public final class UserMessageCell: UITableViewCell {
    public static let reuseID = "UserMessageCell"

    private let bubbleView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14.5, weight: .regular)
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        contentView.addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)

        let maxWidth = UIScreen.main.bounds.width * 0.78

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 50),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(with message: ChatMessage) {
        messageLabel.text = message.text
    }
}

// MARK: - Ячейка сообщения Gemini

public final class AssistantMessageCell: UITableViewCell {
    public static let reuseID = "AssistantMessageCell"

    private var rawText: String = ""

    private let iconView: UIImageView = {
        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iv.image = UIImage(systemName: "sparkles", withConfiguration: config)
        iv.tintColor = .systemPurple
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let contentTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private lazy var copyButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        btn.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: config), for: .normal)
        btn.tintColor = .secondaryLabel
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
        return btn
    }()

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        contentView.addSubview(iconView)
        contentView.addSubview(contentTextView)
        contentView.addSubview(copyButton)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            contentTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            contentTextView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            contentTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

            copyButton.topAnchor.constraint(equalTo: contentTextView.bottomAnchor, constant: 4),
            copyButton.leadingAnchor.constraint(equalTo: contentTextView.leadingAnchor),
            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 26),
            copyButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleCopy() {
        UIPasteboard.general.string = rawText

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        UIView.animate(withDuration: 0.15, animations: {
            self.copyButton.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
            self.copyButton.tintColor = .systemGreen
        }) { _ in
            UIView.animate(withDuration: 0.25) {
                self.copyButton.transform = .identity
                self.copyButton.tintColor = .secondaryLabel
            }
        }
    }

    public func configure(with message: ChatMessage) {
        self.rawText = message.text

        Task { @MainActor in
            let attributed = await NativeMarkdownRenderer.shared.renderAsync(message.text)
            self.contentTextView.attributedText = attributed
        }
    }
}
