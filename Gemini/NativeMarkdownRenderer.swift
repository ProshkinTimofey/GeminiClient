import UIKit

public final class NativeMarkdownRenderer: @unchecked Sendable {
    public static let shared = NativeMarkdownRenderer()

    private let cache = NSCache<NSString, NSAttributedString>()

    private init() {
        cache.countLimit = 150
    }

    public func renderAsync(_ text: String) async -> NSAttributedString {
        let key = text as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await Task.detached(priority: .userInitiated) {
            let rendered = self.parse(text)
            self.cache.setObject(rendered, forKey: key)
            return rendered
        }.value
    }

    public func parse(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        let bodyFont = UIFont.systemFont(ofSize: 14.5, weight: .regular)
        let bodyColor = UIColor.label
        let codeFont = UIFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let codeBgColor = UIColor.secondarySystemBackground

        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = 3.0
        baseParagraph.paragraphSpacing = 8.0

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: bodyColor,
            .paragraphStyle: baseParagraph
        ]

        let codeBlockRegex = try? NSRegularExpression(pattern: "```([a-zA-Z0-9_-]*)\n([\\s\\S]*?)```", options: [])
        let fullRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)

        var lastIndex = 0
        let matches = codeBlockRegex?.matches(in: markdown, options: [], range: fullRange) ?? []

        for match in matches {
            let textRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
            if textRange.length > 0, let range = Range(textRange, in: markdown) {
                let textChunk = String(markdown[range])
                result.append(parseFormattedText(textChunk, baseAttributes: baseAttributes))
            }

            if let contentRange = Range(match.range(at: 2), in: markdown) {
                let codeContent = String(markdown[contentRange]).trimmingCharacters(in: .newlines)
                
                let codeParagraph = NSMutableParagraphStyle()
                codeParagraph.lineSpacing = 2.0
                codeParagraph.paragraphSpacing = 10.0
                codeParagraph.headIndent = 6.0
                codeParagraph.firstLineHeadIndent = 6.0

                let codeBlockAttr: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    .foregroundColor: UIColor.label,
                    .backgroundColor: codeBgColor,
                    .paragraphStyle: codeParagraph
                ]

                let codeString = NSAttributedString(string: "\n" + codeContent + "\n\n", attributes: codeBlockAttr)
                result.append(codeString)
            }

            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < markdown.utf16.count {
            let tailRange = NSRange(location: lastIndex, length: markdown.utf16.count - lastIndex)
            if let range = Range(tailRange, in: markdown) {
                let tailChunk = String(markdown[range])
                result.append(parseFormattedText(tailChunk, baseAttributes: baseAttributes))
            }
        }

        return result
    }

    private func parseFormattedText(_ text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let mutable = NSMutableAttributedString(string: text, attributes: baseAttributes)

        applyRegex(to: mutable, pattern: "^#{1,3}\\s+(.*)$", options: .anchorsMatchLines) { matchString in
            return [
                .font: UIFont.systemFont(ofSize: 16.5, weight: .bold),
                .foregroundColor: UIColor.label
            ]
        }

        applyRegex(to: mutable, pattern: "^[\\*\\-]\\s+", options: .anchorsMatchLines) { _ in
            return [
                .font: UIFont.systemFont(ofSize: 14.5, weight: .bold),
                .foregroundColor: UIColor.systemBlue
            ]
        }

        applyRegex(to: mutable, pattern: "\\*\\*(.*?)\\*\\*") { _ in
            return [.font: UIFont.systemFont(ofSize: 14.5, weight: .bold)]
        }

        applyRegex(to: mutable, pattern: "(?<!\\*)\\*(?!\\*)(.*?)(?<!\\*)\\*(?!\\*)") { _ in
            return [.font: UIFont.italicSystemFont(ofSize: 14.5)]
        }

        applyRegex(to: mutable, pattern: "`([^`]+)`") { _ in
            return [
                .font: UIFont.monospacedSystemFont(ofSize: 13.0, weight: .medium),
                .backgroundColor: UIColor.secondarySystemBackground
            ]
        }

        cleanMarkdownMarkers(in: mutable)

        return mutable
    }

    private func applyRegex(
        to attrString: NSMutableAttributedString,
        pattern: String,
        options: NSRegularExpression.Options = [],
        attributeProvider: (String) -> [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let matches = regex.matches(in: attrString.string, options: [], range: NSRange(location: 0, length: attrString.length))

        for match in matches {
            let matchedString = (attrString.string as NSString).substring(with: match.range)
            let attrs = attributeProvider(matchedString)
            attrString.addAttributes(attrs, range: match.range)
        }
    }

    private func cleanMarkdownMarkers(in attrString: NSMutableAttributedString) {
        let patterns = ["\\*\\*", "(?<!\\*)\\*(?!\\*)", "`"]
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: []) else { continue }
            while let match = regex.firstMatch(in: attrString.string, options: [], range: NSRange(location: 0, length: attrString.length)) {
                attrString.replaceCharacters(in: match.range, with: "")
            }
        }
    }
}
