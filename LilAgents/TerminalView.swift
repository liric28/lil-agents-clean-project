import AppKit
import QuartzCore

class TerminalView: NSView {
    private let transcriptContainer = NSView()
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let inputField = NSTextField()
    // Status badge for displaying session status on the right side of input
    private let statusBadge = NSView()
    private let inputBgView = NSView()
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var statusSweepLayer: CAGradientLayer?
    var onSendMessage: ((String) -> Void)?
    var onClearRequested: (() -> Void)?
    var onPromptResponse: ((AgentPromptResponse) -> Void)?
    var provider: AgentProvider = .claude {
        didSet {
            updatePlaceholder()
        }
    }

    private let promptContainer = NSView()
    private let promptTitleLabel = NSTextField(labelWithString: "")
    private let promptDetailLabel = NSTextField(labelWithString: "")
    private let promptPrimaryButton = NSButton(title: "", target: nil, action: nil)
    private let promptSecondaryButton = NSButton(title: "", target: nil, action: nil)
    private var promptOptionButtons: [NSButton] = []
    private var currentPrompt: AgentPrompt?
    private var currentAssistantText = ""
    private var lastAssistantText = ""
    private var isStreaming = false
    private var showingSessionMessage = false
    private let inputHeight: CGFloat = 30
    private let basePadding: CGFloat = 10
    private let bottomInset: CGFloat = 6

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
        let placeholder = currentPrompt?.requiresTextInput == true
            ? (currentPrompt?.placeholder ?? "Reply…")
            : provider.inputPlaceholder
        inputField.placeholderString = placeholder
        inputField.font = t.font
    }

    private func setupViews() {
        let t = theme
        let isMochaStyle = t.name == "Mocha"

        transcriptContainer.wantsLayer = true
        transcriptContainer.layer?.backgroundColor = isMochaStyle ? NSColor.clear.cgColor : t.inputBg.cgColor
        transcriptContainer.layer?.cornerRadius = 12
        transcriptContainer.layer?.cornerCurve = .continuous
        transcriptContainer.layer?.borderWidth = isMochaStyle ? 0 : 1
        transcriptContainer.layer?.borderColor = t.separatorColor.withAlphaComponent(0.22).cgColor
        addSubview(transcriptContainer)

        scrollView.frame = .zero
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

        promptContainer.wantsLayer = true
        promptContainer.layer?.backgroundColor = t.inputBg.cgColor
        promptContainer.layer?.cornerRadius = 10
        promptContainer.layer?.cornerCurve = .continuous
        promptContainer.layer?.borderWidth = isMochaStyle ? 0 : 1
        promptContainer.layer?.borderColor = t.separatorColor.withAlphaComponent(0.55).cgColor
        promptContainer.isHidden = true

        promptTitleLabel.lineBreakMode = .byTruncatingTail
        promptDetailLabel.lineBreakMode = .byWordWrapping
        promptDetailLabel.maximumNumberOfLines = 0

        promptPrimaryButton.target = self
        promptPrimaryButton.action = #selector(promptPrimaryTapped)
        promptSecondaryButton.target = self
        promptSecondaryButton.action = #selector(promptSecondaryTapped)

        promptContainer.addSubview(promptTitleLabel)
        promptContainer.addSubview(promptDetailLabel)
        promptContainer.addSubview(promptPrimaryButton)
        promptContainer.addSubview(promptSecondaryButton)
        addSubview(promptContainer)

        // Input background view
        inputBgView.wantsLayer = true
        inputBgView.layer?.cornerRadius = t.inputCornerRadius
        addSubview(inputBgView)

        // Input field - transparent, no border
        inputField.frame = .zero
        inputField.autoresizingMask = [.width]
        inputField.focusRingType = .none
        inputField.isEditable = true
        inputField.font = t.font
        inputField.textColor = t.textPrimary
        inputField.drawsBackground = false
        inputField.isBezeled = false
        updatePlaceholder()
        inputField.target = self
        inputField.action = #selector(inputSubmitted)
        addSubview(inputField)

        // Setup status badge (hidden by default)
        statusBadge.wantsLayer = true
        statusBadge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.14).cgColor
        statusBadge.layer?.cornerRadius = 9
        statusBadge.layer?.cornerCurve = .continuous
        statusBadge.layer?.masksToBounds = true
        statusBadge.isHidden = true
        addSubview(statusBadge)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        statusDot.isHidden = true
        statusBadge.addSubview(statusDot)

        statusLabel.font = t.font.withSize(10)
        statusLabel.textColor = t.textPrimary.withAlphaComponent(0.75)
        statusLabel.backgroundColor = .clear
        statusLabel.isBordered = false
        statusLabel.isEditable = false
        statusLabel.lineBreakMode = .byClipping
        statusLabel.isHidden = true
        statusLabel.stringValue = "Ready"
        statusBadge.addSubview(statusLabel)

        refreshPromptAppearance()
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let t = theme
        let isMochaStyle = t.name == "Mocha"
        // Mocha style: no left padding, right padding to align with title bar buttons
        let leftPadding: CGFloat = isMochaStyle ? 10 : basePadding
        let rightPadding: CGFloat = isMochaStyle ? 28 : basePadding

        // Status badge dimensions
        let statusBadgeWidth: CGFloat = 80
        let statusBadgeHeight: CGFloat = 20

        // Input field width accounting for status badge (20pt gap)
        let statusBadgeGap: CGFloat = 20
        let inputWidth = isMochaStyle ? bounds.width - leftPadding - rightPadding - statusBadgeWidth - statusBadgeGap : bounds.width - leftPadding - rightPadding

        // Input field
        let promptHeight = self.promptHeight(for: inputWidth)

        inputField.frame = NSRect(
            x: leftPadding*2,
            y: leftPadding + 3,
            width: inputWidth - 2*leftPadding,
            height: inputHeight - 10
        )
        inputBgView.frame = NSRect(
            x: leftPadding,
            y: leftPadding,
            width: inputWidth,
            height: inputHeight
        )
        inputBgView.layer?.backgroundColor = t.inputBg.withAlphaComponent(isMochaStyle ? 0.76 : 1.0).cgColor
        if !isMochaStyle {
            inputBgView.layer?.borderWidth = 1
            inputBgView.layer?.borderColor = t.separatorColor.withAlphaComponent(0.32).cgColor
        }

        // Status badge to the right of input field, vertically centered with it
        if isMochaStyle {
            let statusBadgeY = bottomInset + statusBadgeHeight*0.5
            statusBadge.frame = NSRect(
                x: leftPadding + inputWidth + statusBadgeGap,
                y: statusBadgeY,
                width: statusBadgeWidth,
                height: statusBadgeHeight
            )
            statusDot.frame = NSRect(x: 8, y: 8, width: 6, height: 6)
            statusLabel.frame = NSRect(x: 18, y: 2, width: statusBadgeWidth - 22, height: 14)
            statusBadge.isHidden = false
            statusDot.isHidden = false
            statusLabel.isHidden = false
        } else {
            statusBadge.isHidden = true
            statusDot.isHidden = true
            statusLabel.isHidden = true
        }

        if promptHeight > 0 {
            promptContainer.isHidden = false
            promptContainer.frame = NSRect(
                x: leftPadding,
                y: inputField.frame.maxY + 8,
                width: bounds.width - leftPadding - rightPadding,
                height: promptHeight
            )
            layoutPromptSubviews()
        } else {
            promptContainer.isHidden = true
            promptContainer.frame = .zero
        }

        let transcriptBottom = promptHeight > 0 ? promptContainer.frame.maxY + 8 : inputField.frame.maxY + 10

        // Transcript container also uses same padding
        let transcriptX = isMochaStyle ? 0 : basePadding
        scrollView.frame = NSRect(
            x: transcriptX,
            y: transcriptBottom,
            width: isMochaStyle ? bounds.width - rightPadding : max(bounds.width - basePadding * 2, 0),
            height: max(bounds.height - transcriptBottom - 8, 0)
        )
        transcriptContainer.frame = scrollView.frame
        textView.frame = scrollView.contentView.bounds
    }

    private func promptHeight(for availableWidth: CGFloat) -> CGFloat {
        guard let prompt = currentPrompt else { return 0 }

        let contentWidth = max(availableWidth - 24, 80)
        let detailHeight = measuredHeight(
            for: prompt.detail,
            width: contentWidth,
            font: theme.font.withSize(11)
        )
        var controlsHeight: CGFloat = 0

        if prompt.usesChoiceButtons {
            controlsHeight = CGFloat(prompt.options.count) * 26 + CGFloat(max(prompt.options.count - 1, 0)) * 6
            if prompt.secondaryActionTitle != nil {
                controlsHeight += 8 + 26
            }
        } else {
            controlsHeight = 26
        }

        return 12 + 14 + 6 + detailHeight + 10 + controlsHeight + 12
    }

    private func measuredHeight(for text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(ceil(rect.height), ceil(font.ascender - font.descender + font.leading))
    }

    private func layoutPromptSubviews() {
        guard let prompt = currentPrompt else { return }

        let t = theme
        let contentWidth = max(promptContainer.bounds.width - 24, 80)
        let titleHeight: CGFloat = 14
        let detailHeight = measuredHeight(
            for: prompt.detail,
            width: contentWidth,
            font: t.font.withSize(11)
        )
        let topY = promptContainer.bounds.height - 12

        promptTitleLabel.frame = NSRect(x: 12, y: topY - titleHeight, width: contentWidth, height: titleHeight)
        promptDetailLabel.frame = NSRect(x: 12, y: promptTitleLabel.frame.minY - 6 - detailHeight, width: contentWidth, height: detailHeight)

        var controlY = promptDetailLabel.frame.minY - 10 - 26
        let buttonWidth = floor((contentWidth - 8) / 2)

        if prompt.usesChoiceButtons {
            promptPrimaryButton.isHidden = true
            for button in promptOptionButtons {
                button.frame = NSRect(x: 12, y: controlY, width: contentWidth, height: 26)
                controlY -= 32
            }

            if let secondaryTitle = prompt.secondaryActionTitle {
                promptSecondaryButton.isHidden = false
                promptSecondaryButton.title = secondaryTitle
                promptSecondaryButton.frame = NSRect(x: 12, y: 12, width: contentWidth, height: 26)
            } else {
                promptSecondaryButton.isHidden = true
            }
        } else {
            promptPrimaryButton.isHidden = false
            promptPrimaryButton.frame = NSRect(x: 12, y: max(controlY, 12), width: buttonWidth, height: 26)

            if let secondaryTitle = prompt.secondaryActionTitle {
                promptSecondaryButton.isHidden = false
                promptSecondaryButton.title = secondaryTitle
                promptSecondaryButton.frame = NSRect(x: promptPrimaryButton.frame.maxX + 8, y: promptPrimaryButton.frame.minY, width: contentWidth - buttonWidth - 8, height: 26)
            } else {
                promptSecondaryButton.isHidden = true
            }
        }
    }

    private func refreshPromptAppearance() {
        let t = theme

        promptTitleLabel.font = t.fontBold.withSize(11)
        promptTitleLabel.textColor = t.textPrimary
        promptDetailLabel.font = t.font.withSize(11)
        promptDetailLabel.textColor = t.textDim.withAlphaComponent(0.96)

        [promptPrimaryButton, promptSecondaryButton].forEach { button in
            button.bezelStyle = .rounded
            button.font = t.font.withSize(11)
        }

        promptPrimaryButton.contentTintColor = t.accentColor
        promptSecondaryButton.contentTintColor = t.textDim
    }

    func resetState() {
        isStreaming = false
        currentAssistantText = ""
        lastAssistantText = ""
        showingSessionMessage = false
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    /// Update the status badge displayed on the right side of input field
    func updateStatus(_ status: String, isWorking: Bool = false) {
        let t = theme
        let isMochaStyle = t.name == "Mocha"
        let accent = t.accentColor

        statusLabel.stringValue = status
        statusLabel.textColor = t.textPrimary.withAlphaComponent(0.75)
        statusDot.layer?.backgroundColor = isWorking ? accent.cgColor : NSColor.systemGreen.cgColor

        // Update sweep animation based on working state
        if isMochaStyle && isWorking {
            startStatusSweepAnimation()
        } else {
            stopStatusSweepAnimation()
        }
    }

    private func startStatusSweepAnimation() {
        guard let badgeLayer = statusBadge.layer else { return }
        let t = theme
        let accent = t.accentColor

        let sweepLayer: CAGradientLayer
        if let existing = statusSweepLayer {
            sweepLayer = existing
        } else {
            let created = CAGradientLayer()
            created.locations = [0, 0.5, 1]
            created.startPoint = CGPoint(x: 0, y: 0.5)
            created.endPoint = CGPoint(x: 1, y: 0.5)
            badgeLayer.addSublayer(created)
            statusSweepLayer = created
            sweepLayer = created
        }

        sweepLayer.colors = [
            NSColor.clear.cgColor,
            accent.withAlphaComponent(0.34).cgColor,
            NSColor.white.withAlphaComponent(0.24).cgColor,
            NSColor.clear.cgColor
        ]
        sweepLayer.locations = [0, 0.38, 0.62, 1]

        let sweepWidth = max(statusBadge.bounds.width * 0.55, 34)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sweepLayer.frame = CGRect(x: -sweepWidth, y: 0, width: sweepWidth, height: statusBadge.bounds.height)
        sweepLayer.isHidden = false
        CATransaction.commit()

        guard sweepLayer.animation(forKey: "workingSweep") == nil else { return }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -sweepWidth / 2
        animation.toValue = statusBadge.bounds.width + sweepWidth / 2
        animation.duration = 1.05
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweepLayer.add(animation, forKey: "workingSweep")
    }

    private func stopStatusSweepAnimation() {
        statusSweepLayer?.removeAnimation(forKey: "workingSweep")
        statusSweepLayer?.isHidden = true
    }

    func showSessionMessage() {
        let t = theme
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: "  \u{2726} new session\n",
            attributes: [.font: t.font, .foregroundColor: t.accentColor]
        ))
        showingSessionMessage = true
    }

    func applyPrompt(_ prompt: AgentPrompt?) {
        currentPrompt = prompt
        rebuildPromptButtons()

        if let prompt {
            promptTitleLabel.stringValue = prompt.title
            promptDetailLabel.stringValue = prompt.detail
            promptPrimaryButton.title = prompt.primaryActionTitle
            promptSecondaryButton.title = prompt.secondaryActionTitle ?? ""
        } else {
            promptTitleLabel.stringValue = ""
            promptDetailLabel.stringValue = ""
        }

        refreshInputMode()
        needsLayout = true
    }

    private func refreshInputMode() {
        updatePlaceholder()

        if let prompt = currentPrompt {
            if prompt.requiresTextInput {
                inputField.isEnabled = true
                inputField.isEditable = true
                inputField.stringValue = prompt.prefilledValue
            } else {
                inputField.stringValue = ""
                inputField.isEnabled = false
                inputField.isEditable = false
            }
        } else {
            inputField.isEnabled = true
            inputField.isEditable = true
        }
    }

    private func rebuildPromptButtons() {
        for button in promptOptionButtons {
            button.removeFromSuperview()
        }
        promptOptionButtons.removeAll()

        guard let prompt = currentPrompt, prompt.usesChoiceButtons else { return }

        let t = theme
        for (index, option) in prompt.options.enumerated() {
            let button = NSButton(title: option, target: self, action: #selector(promptOptionTapped(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.font = t.font.withSize(11)
            button.contentTintColor = t.accentColor
            promptContainer.addSubview(button)
            promptOptionButtons.append(button)
        }
    }

    // MARK: - Input

    @objc private func inputSubmitted() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if currentPrompt?.requiresTextInput == true {
            inputField.stringValue = ""
            onPromptResponse?(.primary(text))
            return
        }

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

    @objc private func promptPrimaryTapped() {
        if currentPrompt?.requiresTextInput == true {
            inputSubmitted()
            return
        }
        onPromptResponse?(.primary(nil))
    }

    @objc private func promptSecondaryTapped() {
        onPromptResponse?(.secondary)
    }

    @objc private func promptOptionTapped(_ sender: NSButton) {
        guard let prompt = currentPrompt, sender.tag >= 0, sender.tag < prompt.options.count else { return }
        onPromptResponse?(.option(sender.tag, prompt.options[sender.tag]))
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
            .font: t.font, .foregroundColor: t.accentColor, .paragraphStyle: para
        ]))
        attributed.append(NSAttributedString(string: "\(text)\n", attributes: [
            .font: t.font, .foregroundColor: t.textPrimary, .paragraphStyle: para
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
            textView.textStorage?.append(renderTranscriptText(cleaned))
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
        ensureNewline()
        textView.textStorage?.append(renderLogLine(prefix: "err  ", body: text + "\n", prefixColor: t.errorColor, bodyColor: t.errorColor.withAlphaComponent(0.9)))
        scrollToBottom()
    }

    func appendToolUse(toolName: String, summary: String) {
        endStreaming()
        ensureNewline()
        let style = toolUseStyle(toolName: toolName, summary: summary)
        textView.textStorage?.append(renderLogLine(prefix: style.prefix, body: style.body + "\n", prefixColor: style.prefixColor, bodyColor: style.bodyColor))
        scrollToBottom()
    }

    func appendToolResult(summary: String, isError: Bool) {
        ensureNewline()
        let style = toolResultStyle(summary: summary, isError: isError)
        textView.textStorage?.append(renderLogLine(prefix: style.prefix, body: style.body + "\n", prefixColor: style.prefixColor, bodyColor: style.bodyColor))
        scrollToBottom()
    }

    func replayHistory(_ messages: [AgentMessage]) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        for msg in messages {
            switch msg.role {
            case .user:
                appendUser(msg.text)
            case .assistant:
                textView.textStorage?.append(renderTranscriptText(msg.text + "\n"))
            case .error:
                appendError(msg.text)
            case .toolUse:
                let style = toolUseStyle(historyText: msg.text)
                textView.textStorage?.append(renderLogLine(prefix: style.prefix, body: style.body + "\n", prefixColor: style.prefixColor, bodyColor: style.bodyColor))
            case .toolResult:
                let isErr = msg.text.hasPrefix("ERROR:")
                let body = isErr ? String(msg.text.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces) : msg.text
                let style = toolResultStyle(summary: body, isError: isErr)
                textView.textStorage?.append(renderLogLine(prefix: style.prefix, body: style.body + "\n", prefixColor: style.prefixColor, bodyColor: style.bodyColor))
            }
        }
        scrollToBottom()
    }

    private func scrollToBottom() {
        // Resize textView to fit content so scroll range is correct
        let contentSize = textView.layoutManager?.usedRect(for: textView.textContainer ?? NSTextContainer()).size
        let neededHeight = max(contentSize?.height ?? 0, scrollView.contentView.bounds.height)
        textView.frame.size.height = neededHeight
        // Scroll to bottom
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, neededHeight - scrollView.contentView.bounds.height)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Transcript Rendering

    private func renderTranscriptText(_ text: String, color: NSColor? = nil) -> NSAttributedString {
        let t = theme
        // 实时输出按原文渲染，避免流式过程中因为 Markdown 解析导致样式跳变。
        return NSAttributedString(string: text, attributes: [
            .font: t.font,
            .foregroundColor: color ?? t.textPrimary
        ])
    }

    private func renderLogLine(prefix: String, body: String, prefixColor: NSColor, bodyColor: NSColor? = nil) -> NSAttributedString {
        let t = theme
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: prefix, attributes: [
            .font: t.font,
            .foregroundColor: prefixColor
        ]))
        line.append(NSAttributedString(string: body, attributes: [
            .font: t.font,
            .foregroundColor: bodyColor ?? t.textDim
        ]))
        return line
    }

    private func toolUseStyle(toolName: String, summary: String) -> (prefix: String, body: String, prefixColor: NSColor, bodyColor: NSColor) {
        let t = theme
        let normalized = toolName.lowercased()
        // 统一把不同 provider 的工具事件压成终端日志行，避免实时流和历史回放显示两套格式。
        switch normalized {
        case "bash", "shell", "command_execution":
            return ("exec ", summary, t.accentColor, t.textPrimary)
        case "filechange", "file_change", "apply_patch", "write", "edit":
            return ("edit ", summary, t.accentColor, t.textPrimary)
        default:
            return ("\(normalized) ", summary, t.accentColor, t.textPrimary)
        }
    }

    private func toolUseStyle(historyText: String) -> (prefix: String, body: String, prefixColor: NSColor, bodyColor: NSColor) {
        if let sep = historyText.firstIndex(of: ":") {
            let name = String(historyText[..<sep]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(historyText[historyText.index(after: sep)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return toolUseStyle(toolName: name, summary: body)
        }
        return toolUseStyle(toolName: "tool", summary: historyText)
    }

    private func toolResultStyle(summary: String, isError: Bool) -> (prefix: String, body: String, prefixColor: NSColor, bodyColor: NSColor) {
        let t = theme
        if isError {
            return ("fail ", summary, t.errorColor, t.errorColor.withAlphaComponent(0.92))
        }
        return ("done ", summary, t.successColor, t.textDim)
    }
}
