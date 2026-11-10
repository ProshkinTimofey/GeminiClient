import UIKit

public final class GrowingInputBarView: UIView, UITextViewDelegate {

    public var onSendMessage: ((String) -> Void)?

    private let minHeight: CGFloat = 40.0
    private let maxHeight: CGFloat = 110.0

    private var textViewHeightConstraint: NSLayoutConstraint!

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont.systemFont(ofSize: 15.0)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.delegate = self
        tv.textContainerInset = UIEdgeInsets(top: 9, left: 6, bottom: 9, right: 6)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Спросить Gemini..."
        label.font = UIFont.systemFont(ofSize: 15.0)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = .systemBlue
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleSend), for: .touchUpInside)
        return button
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemBackground

        let separator = UIView()
        separator.backgroundColor = .separator.withAlphaComponent(0.2)
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        addSubview(containerView)
        containerView.addSubview(placeholderLabel)
        containerView.addSubview(textView)
        addSubview(sendButton)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: minHeight)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            containerView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 6),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            textViewHeightConstraint,

            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 10),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -2),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    @objc private func handleSend() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        onSendMessage?(text)
        textView.text = ""
        textViewDidChange(textView)
    }

    public func setGenerating(_ isGenerating: Bool) {
        sendButton.isEnabled = !isGenerating && !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.alpha = isGenerating ? 0.3 : 1.0
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty

        let cleanText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        sendButton.isEnabled = !cleanText.isEmpty

        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .infinity))
        let targetHeight = min(max(size.height, minHeight), maxHeight)

        if textViewHeightConstraint.constant != targetHeight {
            textViewHeightConstraint.constant = targetHeight
            textView.isScrollEnabled = (size.height > maxHeight)
            layoutIfNeeded()
        }
    }
}
