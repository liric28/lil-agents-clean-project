import AppKit

class PaddedTextFieldCell: NSTextFieldCell {
    private let inset = NSSize(width: 8, height: 2)
    var fieldBackgroundColor: NSColor?
    var fieldCornerRadius: CGFloat = 4

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if let bg = fieldBackgroundColor {
            let path = NSBezierPath(roundedRect: cellFrame, xRadius: fieldCornerRadius, yRadius: fieldCornerRadius)
            bg.setFill()
            path.fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        return base.insetBy(dx: inset.width, dy: inset.height)
    }

    private func configureEditor(_ textObj: NSText) {
        if let color = textColor {
            textObj.textColor = color
        }
        if let tv = textObj as? NSTextView {
            tv.insertionPointColor = textColor ?? .textColor
            tv.drawsBackground = false
            tv.backgroundColor = .clear
        }
        textObj.font = font
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        configureEditor(textObj)
        super.edit(withFrame: rect.insetBy(dx: inset.width, dy: inset.height), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        configureEditor(textObj)
        super.select(withFrame: rect.insetBy(dx: inset.width, dy: inset.height), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

//    private lazy var customFieldEditor: InputFieldEditor = {
//        let editor = InputFieldEditor(frame: .zero)
//        editor.drawsBackground = false
//        editor.backgroundColor = .clear
//        editor.isRichText = false
//        editor.importsGraphics = false
//        editor.isEditable = true
//        editor.isSelectable = true
//        return editor
//    }()
//
//    override func fieldEditor(for controlView: NSView) -> NSTextView? {
//        return customFieldEditor
//    }
}

private class InputFieldEditor: NSTextView {
    var onReturnKey: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36 { // Return key
            onReturnKey?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

class TerminalView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let inputField = NSTextField()
    var onSendMessage: ((String) -> Void)?
    var onClearRequested: (() -> Void)?
    var provider: AgentProvider = .claude {
        didSet {
            updatePlaceholder()
        }
    }

    // MARK: - Status Indicator
    enum Status {
        case ready
        case thinking
        case working
        case error
    }

    private let statusContainer = NSView()
    private let statusDot = NSView()
    private let statusLabel = NSTextField()
    private var currentStatus: Status = .ready

    var status: Status = .ready {
        didSet {
            updateStatusDisplay()
        }
    }

    // MARK: - Shimmer Animation
    private var shimmerLayer: CAGradientLayer?
    private var shimmerAnimation: CABasicAnimation?

    private func startShimmerAnimation() {
        stopShimmerAnimation()

        let gradient = CAGradientLayer()
        gradient.frame = statusContainer.bounds
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.2).cgColor,
            NSColor.clear.cgColor
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        statusContainer.layer?.addSublayer(gradient)
        shimmerLayer = gradient

        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1.0, -0.5, 0.0]
        anim.toValue = [1.0, 1.5, 2.0]
        anim.duration = 2.0
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: "shimmer")
        shimmerAnimation = anim
    }

    private func stopShimmerAnimation() {
        shimmerLayer?.removeAllAnimations()
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil
        shimmerAnimation = nil
    }

    private func updateShimmerFrame() {
        shimmerLayer?.frame = statusContainer.bounds
    }

    private func setupStatusIndicator() {

        // Container - semi-transparent rounded bar
        statusContainer.wantsLayer = true
        statusContainer.layer?.backgroundColor = NSColor(white: 0, alpha: 0.15).cgColor
        statusContainer.layer?.cornerRadius = 10

        // Dot
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        updateStatusDotColor()

        // Label
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.stringValue = "Ready"
        statusLabel.alignment = .left
        statusLabel.lineBreakMode = .byClipping
        statusLabel.cell?.wraps = false
        statusLabel.cell?.isScrollable = true

        statusContainer.addSubview(statusDot)
        statusContainer.addSubview(statusLabel)
        addSubview(statusContainer)
    }

    private func updateStatusDotColor() {
        switch currentStatus {
        case .ready:
            statusDot.layer?.backgroundColor = NSColor(red: 166/255, green: 227/255, blue: 161/255, alpha: 1).cgColor
        case .thinking:
            statusDot.layer?.backgroundColor = NSColor(red: 137/255, green: 180/255, blue: 250/255, alpha: 1).cgColor
        case .working:
            statusDot.layer?.backgroundColor = NSColor(red: 137/255, green: 180/255, blue: 250/255, alpha: 1).cgColor
        case .error:
            statusDot.layer?.backgroundColor = NSColor(red: 243/255, green: 139/255, blue: 168/255, alpha: 1).cgColor
        }
    }

    private func updateStatusDisplay() {
        currentStatus = status
        updateStatusDotColor()
        switch status {
        case .ready:
            statusLabel.stringValue = "Ready"
            stopShimmerAnimation()
        case .thinking:
            statusLabel.stringValue = "Thinking"
            startShimmerAnimation()
        case .working:
            statusLabel.stringValue = "Working"
            startShimmerAnimation()
        case .error:
            statusLabel.stringValue = "Error"
            stopShimmerAnimation()
        }
    }

    private func layoutStatusIndicator(inputHeight: CGFloat, padding: CGFloat) {
        let statusHeight: CGFloat = 20
        let statusY: CGFloat = inputHeight + 10

        // Get text size with a larger width
        let textSize = statusLabel.sizeThatFits(NSSize(width: 1000, height: 16))
        let dotSize: CGFloat = 8
        let spacing: CGFloat = 6
        let sidePadding: CGFloat = 16

        // Container just fits content with padding
        statusContainer.frame = NSRect(
            x: padding, y: statusY,
            width: dotSize + spacing + textSize.width + sidePadding * 2 + 10, height: statusHeight
        )

        // Remove existing constraints
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Dot centered vertically and at leading position
            statusDot.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
            statusDot.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: sidePadding),
            statusDot.widthAnchor.constraint(equalToConstant: dotSize),
            statusDot.heightAnchor.constraint(equalToConstant: dotSize),

            // Text centered vertically after dot
            statusLabel.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: spacing),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -sidePadding)
        ])
    }

    private var currentAssistantText = ""
    private var lastAssistantText = ""
    private var isStreaming = false
    private var showingSessionMessage = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    var characterColor: NSColor?
    var themeOverride: PopoverTheme?
    var theme: PopoverTheme {
        var t = themeOverride ?? PopoverTheme.current
        if let color = characterColor { t = t.withCharacterColor(color) }
        t = t.withCustomFont()
        return t
    }

    // MARK: - Setup

    private func updatePlaceholder() {
        let t = theme
        let placeholderFont = NSFont.systemFont(ofSize: t.font.pointSize - 2, weight: t.font.fontDescriptor.symbolicTraits.contains(.bold) ? .semibold : .regular)
        inputField.placeholderAttributedString = NSAttributedString(
            string: provider.inputPlaceholder,
            attributes: [.font: placeholderFont, .foregroundColor: t.textDim]
        )
    }

    private func setupViews() {
        let t = theme
        let inputHeight: CGFloat = 30
        let padding: CGFloat = 10

        scrollView.frame = NSRect(
            x: padding, y: inputHeight + padding + 26,
            width: frame.width - padding * 2,
            height: frame.height - inputHeight - padding - 30
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        textView.frame = scrollView.contentView.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = t.textPrimary
        textView.font = t.font
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 2, height: 4)
        let defaultPara = NSMutableParagraphStyle()
        defaultPara.paragraphSpacing = 8
        textView.defaultParagraphStyle = defaultPara
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: t.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        addSubview(scrollView)

        inputField.frame = NSRect(
            x: padding + 10, y: 6,
            width: frame.width - padding * 2,
            height: inputHeight
        )
        inputField.autoresizingMask = [.width]
        inputField.focusRingType = .none
        let paddedCell = PaddedTextFieldCell(textCell: "")
        paddedCell.isEditable = true
        paddedCell.isScrollable = true
        paddedCell.font = t.titleFont
        paddedCell.textColor = t.textPrimary
        paddedCell.drawsBackground = false
        paddedCell.isBezeled = false
        paddedCell.fieldBackgroundColor = nil
        paddedCell.fieldCornerRadius = 0
        inputField.cell = paddedCell
        updatePlaceholder()
        inputField.target = self
        inputField.action = #selector(inputSubmitted)
        addSubview(inputField)
        
        if PopoverTheme.current.name == "Mocha" {
            let spinner = ProcessingSpinner(frame: NSRect(x: 0, y: 13, width: 30, height: 30))
            addSubview(spinner)
        } else {
            let spinner = RunningIcon(size: 12, color: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1.0))
            spinner.frame.origin = NSPoint(x: 11, y: 22)
            addSubview(spinner)
        }
        
        setupStatusIndicator()
        layoutStatusIndicator(inputHeight: inputHeight, padding: padding)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inputHeight: CGFloat = 30
        let padding: CGFloat = 10

        scrollView.frame = NSRect(
            x: padding, y: inputHeight + padding + 26,
            width: newSize.width - padding * 2,
            height: newSize.height - inputHeight - padding - 30
        )

        inputField.frame = NSRect(
            x: padding + 10, y: 6,
            width: newSize.width - padding * 2,
            height: inputHeight
        )

        layoutStatusIndicator(inputHeight: inputHeight, padding: padding)
        updateShimmerFrame()
    }

    func resetState() {
        isStreaming = false
        currentAssistantText = ""
        lastAssistantText = ""
        showingSessionMessage = false
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    func showSessionMessage() {
        let t = theme
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: "  \u{2726} new session\n",
            attributes: [.font: t.font, .foregroundColor: t.accentColor]
        ))
        showingSessionMessage = true
    }

    // MARK: - Input

    @objc private func inputSubmitted() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""

        if handleSlashCommand(text) { return }

        if showingSessionMessage {
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            showingSessionMessage = false
        }
        appendUser(text)
        isStreaming = true
        currentAssistantText = ""
        onSendMessage?(text)
    }

    // MARK: - Slash Commands

    func handleSlashCommandPublic(_ text: String) {
        _ = handleSlashCommand(text)
    }

    private func handleSlashCommand(_ text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let cmd = text.lowercased().trimmingCharacters(in: .whitespaces)

        switch cmd {
        case "/clear":
            resetState()
            onClearRequested?()
            return true

        case "/copy":
            let toCopy = lastAssistantText.isEmpty ? "nothing to copy yet" : lastAssistantText
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(toCopy, forType: .string)
            let t = theme
            textView.textStorage?.append(NSAttributedString(
                string: "  ✓ copied to clipboard\n",
                attributes: [.font: t.font, .foregroundColor: t.successColor]
            ))
            scrollToBottom()
            return true

        case "/help":
            let t = theme
            let help = NSMutableAttributedString()
            help.append(NSAttributedString(string: "  lil agents — slash commands\n",
                attributes: [.font: t.fontBold, .foregroundColor: t.accentColor]))
            help.append(NSAttributedString(string: "  /clear  ", attributes: [.font: t.fontBold, .foregroundColor: t.textPrimary]))
            help.append(NSAttributedString(string: "clear chat history\n", attributes: [.font: t.font, .foregroundColor: t.textDim]))
            help.append(NSAttributedString(string: "  /copy   ", attributes: [.font: t.fontBold, .foregroundColor: t.textPrimary]))
            help.append(NSAttributedString(string: "copy last response\n", attributes: [.font: t.font, .foregroundColor: t.textDim]))
            help.append(NSAttributedString(string: "  /help   ", attributes: [.font: t.fontBold, .foregroundColor: t.textPrimary]))
            help.append(NSAttributedString(string: "show this message\n", attributes: [.font: t.font, .foregroundColor: t.textDim]))
            textView.textStorage?.append(help)
            scrollToBottom()
            return true

        default:
            let t = theme
            textView.textStorage?.append(NSAttributedString(
                string: "  unknown command: \(text) (try /help)\n",
                attributes: [.font: t.font, .foregroundColor: t.errorColor]
            ))
            scrollToBottom()
            return true
        }
    }

    // MARK: - Append Methods

    private var messageSpacing: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 8
        return p
    }

    private func ensureNewline() {
        if let storage = textView.textStorage, storage.length > 0 {
            if !storage.string.hasSuffix("\n") {
                storage.append(NSAttributedString(string: "\n"))
            }
        }
    }

    func appendUser(_ text: String) {
        let t = theme
        ensureNewline()
        let para = messageSpacing
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "> ", attributes: [
            .font: t.fontBold, .foregroundColor: t.accentColor, .paragraphStyle: para
        ]))
        attributed.append(NSAttributedString(string: "\(text)\n", attributes: [
            .font: t.fontBold, .foregroundColor: t.textPrimary, .paragraphStyle: para
        ]))
        textView.textStorage?.append(attributed)
        scrollToBottom()
    }

    func appendStreamingText(_ text: String) {
        var cleaned = text
        if currentAssistantText.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "^\n+", with: "", options: .regularExpression)
        }
        currentAssistantText += cleaned
        if !cleaned.isEmpty {
            textView.textStorage?.append(renderMarkdown(cleaned))
            scrollToBottom()
        }
    }

    func endStreaming() {
        if isStreaming {
            isStreaming = false
            if !currentAssistantText.isEmpty {
                lastAssistantText = currentAssistantText
            }
            currentAssistantText = ""
        }
    }

    func appendError(_ text: String) {
        let t = theme
        textView.textStorage?.append(NSAttributedString(string: text + "\n", attributes: [
            .font: t.font, .foregroundColor: t.errorColor
        ]))
        scrollToBottom()
    }

    func appendToolUse(toolName: String, summary: String) {
        let t = theme
        endStreaming()
        let block = NSMutableAttributedString()
        block.append(NSAttributedString(string: "  \(toolName.uppercased()) ", attributes: [
            .font: t.fontBold, .foregroundColor: t.accentColor
        ]))
        block.append(NSAttributedString(string: "\(summary)\n", attributes: [
            .font: t.font, .foregroundColor: t.textDim
        ]))
        textView.textStorage?.append(block)
        scrollToBottom()
    }

    func appendToolResult(summary: String, isError: Bool) {
        let t = theme
        let color = isError ? t.errorColor : t.successColor
        let prefix = isError ? "  FAIL " : "  DONE "
        let block = NSMutableAttributedString()
        block.append(NSAttributedString(string: prefix, attributes: [
            .font: t.fontBold, .foregroundColor: color
        ]))
        block.append(NSAttributedString(string: "\(summary.isEmpty ? "" : summary)\n", attributes: [
            .font: t.font, .foregroundColor: t.textDim
        ]))
        textView.textStorage?.append(block)
        scrollToBottom()
    }

    func replayHistory(_ messages: [AgentMessage]) {
        let t = theme
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        for msg in messages {
            switch msg.role {
            case .user:
                appendUser(msg.text)
            case .assistant:
                textView.textStorage?.append(renderMarkdown(msg.text + "\n"))
            case .error:
                appendError(msg.text)
            case .toolUse:
                textView.textStorage?.append(NSAttributedString(string: "  \(msg.text)\n", attributes: [
                    .font: t.font, .foregroundColor: t.accentColor
                ]))
            case .toolResult:
                let isErr = msg.text.hasPrefix("ERROR:")
                textView.textStorage?.append(NSAttributedString(string: "  \(msg.text)\n", attributes: [
                    .font: t.font, .foregroundColor: isErr ? t.errorColor : t.successColor
                ]))
            }
        }
        scrollToBottom()
    }

    private func scrollToBottom() {
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: - Markdown Rendering

    private func renderMarkdown(_ text: String) -> NSAttributedString {
        let t = theme
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockLang = ""
        var codeLines: [String] = []

        for (i, line) in lines.enumerated() {
            let suffix = i < lines.count - 1 ? "\n" : ""

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let codeText = codeLines.joined(separator: "\n")
                    let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
                    result.append(NSAttributedString(string: codeText + "\n", attributes: [
                        .font: codeFont, .foregroundColor: t.textPrimary, .backgroundColor: t.inputBg
                    ]))
                    inCodeBlock = false
                    codeLines = []
                } else {
                    inCodeBlock = true
                    codeBlockLang = String(line.dropFirst(3))
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            if line.hasPrefix("### ") {
                result.append(NSAttributedString(string: String(line.dropFirst(4)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize, weight: .bold), .foregroundColor: t.accentColor
                ]))
            } else if line.hasPrefix("## ") {
                result.append(NSAttributedString(string: String(line.dropFirst(3)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize + 1, weight: .bold), .foregroundColor: t.accentColor
                ]))
            } else if line.hasPrefix("# ") {
                result.append(NSAttributedString(string: String(line.dropFirst(2)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize + 2, weight: .bold), .foregroundColor: t.accentColor
                ]))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                result.append(NSAttributedString(string: "  \u{2022} ", attributes: [
                    .font: t.font, .foregroundColor: t.accentColor
                ]))
                result.append(renderInlineMarkdown(content + suffix, theme: t))
            } else {
                result.append(renderInlineMarkdown(line + suffix, theme: t))
            }
        }

        if inCodeBlock && !codeLines.isEmpty {
            let codeText = codeLines.joined(separator: "\n")
            let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
            result.append(NSAttributedString(string: codeText + "\n", attributes: [
                .font: codeFont, .foregroundColor: t.textPrimary, .backgroundColor: t.inputBg
            ]))
        }

        return result
    }

    private func renderInlineMarkdown(_ text: String, theme t: PopoverTheme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "`" {
                let afterTick = text.index(after: i)
                if afterTick < text.endIndex, let closeIdx = text[afterTick...].firstIndex(of: "`") {
                    let code = String(text[afterTick..<closeIdx])
                    let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 0.5, weight: .regular)
                    result.append(NSAttributedString(string: code, attributes: [
                        .font: codeFont, .foregroundColor: t.accentColor, .backgroundColor: t.inputBg
                    ]))
                    i = text.index(after: closeIdx)
                    continue
                }
            }
            if text[i] == "*",
               text.index(after: i) < text.endIndex, text[text.index(after: i)] == "*" {
                let start = text.index(i, offsetBy: 2)
                if start < text.endIndex, let range = text.range(of: "**", range: start..<text.endIndex) {
                    let bold = String(text[start..<range.lowerBound])
                    result.append(NSAttributedString(string: bold, attributes: [
                        .font: t.fontBold, .foregroundColor: t.textPrimary
                    ]))
                    i = range.upperBound
                    continue
                }
            }
            if text[i] == "[" {
                let afterBracket = text.index(after: i)
                if afterBracket < text.endIndex,
                   let closeBracket = text[afterBracket...].firstIndex(of: "]") {
                    let parenStart = text.index(after: closeBracket)
                    if parenStart < text.endIndex && text[parenStart] == "(" {
                        let afterParen = text.index(after: parenStart)
                        if afterParen < text.endIndex,
                           let closeParen = text[afterParen...].firstIndex(of: ")") {
                            let linkText = String(text[afterBracket..<closeBracket])
                            let urlStr = String(text[afterParen..<closeParen])
                            var attrs: [NSAttributedString.Key: Any] = [
                                .font: t.font,
                                .foregroundColor: t.accentColor,
                                .underlineStyle: NSUnderlineStyle.single.rawValue
                            ]
                            if let url = URL(string: urlStr) {
                                attrs[.link] = url
                                attrs[.cursor] = NSCursor.pointingHand
                            }
                            result.append(NSAttributedString(string: linkText, attributes: attrs))
                            i = text.index(after: closeParen)
                            continue
                        }
                    }
                }
            }
            if text[i] == "h" {
                let remaining = String(text[i...])
                if remaining.hasPrefix("https://") || remaining.hasPrefix("http://") {
                    var j = i
                    while j < text.endIndex && !text[j].isWhitespace && text[j] != ")" && text[j] != ">" {
                        j = text.index(after: j)
                    }
                    let urlStr = String(text[i..<j])
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: t.font,
                        .foregroundColor: t.accentColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    if let url = URL(string: urlStr) {
                        attrs[.link] = url
                    }
                    result.append(NSAttributedString(string: urlStr, attributes: attrs))
                    i = j
                    continue
                }
            }
            result.append(NSAttributedString(string: String(text[i]), attributes: [
                .font: t.font, .foregroundColor: t.textPrimary
            ]))
            i = text.index(after: i)
        }
        return result
    }
}

///////////////////////////////////////

class ProcessingSpinner: NSView {
    
    // MARK: - Properties
    private let textField = NSTextField()
    private let symbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let color = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)
    private var currentIndex = 0
    private var timer: Timer?
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        startAnimating()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        startAnimating()
    }
    
    // MARK: - Setup
    private func setupUI() {
        // 配置 TextField
        textField.stringValue = symbols[0]
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        textField.textColor = color
        textField.alignment = .center
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.frame = CGRect(x: 0, y: 0, width: 12, height: 30)
        
        addSubview(textField)
        
        // 使用 Auto Layout 居中
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: 12)
        ])
    }
    
    // MARK: - Animation Control
    func startAnimating() {
        stopAnimating()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentIndex = (self.currentIndex + 1) % self.symbols.count
            self.textField.stringValue = self.symbols[self.currentIndex]
        }
    }
    
    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Cleanup
    deinit {
        stopAnimating()
    }
}

////////////////////////////////

class RunningIcon: NSView {
    
    // MARK: - Properties
    private let size: CGFloat
    private let color: NSColor
    private var rotation: CGFloat = 0
    private var displayLink: CVDisplayLink?
    
    init(size: CGFloat = 12, color: NSColor = .cyan) {
        self.size = size
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        startAnimating()
    }
    
    required init?(coder: NSCoder) {
        self.size = 12
        self.color = .cyan
        super.init(coder: coder)
        wantsLayer = true
        startAnimating()
    }
    
    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let scale = size / 30.0
        let dotSize: CGFloat = 4 * scale
        
        // 实心点坐标
        let solidDots: [(CGFloat, CGFloat)] = [
            (15, 3), (7, 7), (15, 7), (23, 7),
            (15, 11), (15, 19), (3, 15), (7, 15),
            (11, 15), (19, 15), (23, 15), (27, 15),
            (7, 23), (15, 23), (23, 23), (15, 27)
        ]
        
        // 半透明点坐标
        let fadedDots: [(CGFloat, CGFloat)] = [
            (11, 11), (19, 11), (11, 19), (19, 19)
        ]
        
        // 保存图形状态并应用旋转
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: rotation * .pi / 180)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        
        // 绘制实心点
        context.setFillColor(color.cgColor)
        for (x, y) in solidDots {
            let rect = CGRect(
                x: x * scale - dotSize/2,
                y: y * scale - dotSize/2,
                width: dotSize,
                height: dotSize
            )
            context.fillEllipse(in: rect)
        }
        
        // 绘制半透明点
        context.setFillColor(color.withAlphaComponent(0.4).cgColor)
        for (x, y) in fadedDots {
            let rect = CGRect(
                x: x * scale - dotSize/2,
                y: y * scale - dotSize/2,
                width: dotSize,
                height: dotSize
            )
            context.fillEllipse(in: rect)
        }
        
        context.restoreGState()
    }
    
    // MARK: - Animation
    private func startAnimating() {
        // 使用 Timer 进行旋转动画
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.rotation += 360.0 / (2.0 * 60.0) // 2秒一圈，60fps
            if self.rotation >= 360 {
                self.rotation -= 360
            }
            self.needsDisplay = true
        }
    }
    
    func stopAnimating() {
        // Timer 会自动管理，这里留空以便外部控制
    }
}

///////////////////////////////////

import Cocoa

class ReadyForInputIndicatorIcon: NSView {
    
    private let color: NSColor
    private let pixels: [(CGFloat, CGFloat)] = [
        (5, 15), (9, 19), (13, 23),
        (17, 19), (21, 15), (25, 11), (29, 7)
    ]
    
    init(size: CGFloat = 14, color: NSColor = .green) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        self.color = .green
        super.init(coder: coder)
        wantsLayer = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let size = bounds.width
        let scale = size / 30.0
        let pixelSize: CGFloat = 4 * scale
        
        // 保存当前图形状态
        context.saveGState()
        
        // 关键：翻转坐标系，使其与 SwiftUI 一致（原点在左上角，Y 轴向下）
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        
        context.setFillColor(color.cgColor)
        
        for (x, y) in pixels {
            let rect = CGRect(
                x: x * scale - pixelSize / 2,
                y: y * scale - pixelSize / 2,
                width: pixelSize,
                height: pixelSize
            )
            context.fill(rect)
        }
        
        // 恢复图形状态
        context.restoreGState()
    }
}
