import AppKit
import QuartzCore

enum IslandBarStatus {
    case ready
    case working
    case approval
    case ask
    case done
    case error

    var label: String {
        switch self {
        case .ready: return "ready"
        case .working: return "working"
        case .approval: return "approval"
        case .ask: return "ask"
        case .done: return "done"
        case .error: return "error"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .done, .error, .ready:
            return true
        case .working, .approval, .ask:
            return false
        }
    }

    var priority: Int {
        switch self {
        case .approval:
            return 50
        case .ask:
            return 40
        case .working:
            return 30
        case .error:
            return 20
        case .done:
            return 10
        case .ready:
            return 0
        }
    }

    var autoClearDelay: TimeInterval? {
        switch self {
        case .ready:
            return 1.0
        case .done:
            return 1.8
        case .error:
            return 2.4
        case .working, .approval, .ask:
            return nil
        }
    }

    static func parse(_ raw: String) -> IslandBarStatus? {
        switch raw.lowercased() {
        case "ready": return .ready
        case "working", "run", "running", "progress": return .working
        case "approval", "approve", "permission": return .approval
        case "ask", "input", "question": return .ask
        case "done", "success", "complete", "completed": return .done
        case "error", "failed", "fail": return .error
        default: return nil
        }
    }
}

struct IslandBarModel {
    let title: String
    let detail: String
    let status: IslandBarStatus
    let theme: PopoverTheme
    let queueCount: Int
}

struct IslandTask {
    let id: String
    let title: String
    let detail: String
    let status: IslandBarStatus
    let theme: PopoverTheme
    let characterName: String?
    let prompt: AgentPrompt?
    let updatedAt: CFTimeInterval
}

final class IslandBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        super.constrainFrameRect(frameRect, to: screen)
    }
}

final class IslandBarView: NSView {
    var onClick: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusDotView = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
    private let queueBadgeView = NSView(frame: .zero)
    private let queueBadgeLabel = NSTextField(labelWithString: "")
    private let pixelStripView = NSView(frame: .zero)
    private var pixelViews: [NSView] = []
    private var sweepLayer: CAGradientLayer?
    private var currentTheme = PopoverTheme.current
    private var currentStatus: IslandBarStatus = .ready
    private var currentQueueCount = 0
    private var isExpanded = false
    private let pixelCount = 14
    private let horizontalPadding: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        // 贴住菜单栏顶部时只保留下边圆角，更接近真实刘海。
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.backgroundColor = NSColor(red: 0/255, green: 0/255, blue: 0/255, alpha: 1).cgColor

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = true
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.alignment = .center
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byClipping
        statusLabel.isHidden = true

        statusDotView.wantsLayer = true
        statusDotView.layer?.cornerRadius = 3
        statusDotView.layer?.masksToBounds = true
        statusDotView.isHidden = true

        queueBadgeView.wantsLayer = true
        queueBadgeView.layer?.cornerRadius = 7
        queueBadgeView.layer?.masksToBounds = true
        queueBadgeView.isHidden = true

        queueBadgeLabel.alignment = .center
        queueBadgeView.addSubview(queueBadgeLabel)

        pixelStripView.wantsLayer = true
        for _ in 0..<pixelCount {
            let pixel = NSView(frame: .zero)
            pixel.wantsLayer = true
            pixel.layer?.cornerRadius = 1.2
            pixel.layer?.masksToBounds = true
            pixel.layer?.opacity = 0.2
            pixelStripView.addSubview(pixel)
            pixelViews.append(pixel)
        }

        addSubview(pixelStripView)
        addSubview(statusDotView)
        addSubview(titleLabel)
        addSubview(statusLabel)
        addSubview(detailLabel)
        addSubview(queueBadgeView)
        setExpanded(false, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func layout() {
        super.layout()

        layoutPixelStrip()

        titleLabel.frame = .zero
        statusLabel.frame = .zero
        statusDotView.frame = .zero

        let queueWidth = !queueBadgeView.isHidden ? queueBadgeView.bounds.width + 12 : 0
        if !queueBadgeView.isHidden {
            queueBadgeView.frame = NSRect(
                x: bounds.width - horizontalPadding - queueBadgeView.bounds.width,
                y: floor((bounds.height - 16) / 2),
                width: queueBadgeView.bounds.width,
                height: 16
            )
            queueBadgeLabel.frame = queueBadgeView.bounds
        } else {
            queueBadgeView.frame = .zero
        }

        // working 态把任务文案放到正中央，其他状态继续让位给左侧像素点和右侧计数。
        let textX: CGFloat
        let textWidth: CGFloat
        if currentStatus == .working {
            textX = horizontalPadding
            textWidth = max(bounds.width - horizontalPadding * 2, 40)
        } else {
            textX = pixelStripView.frame.maxX + 14
            textWidth = max(bounds.width - textX - horizontalPadding - queueWidth, 40)
        }
        detailLabel.frame = NSRect(
            x: textX,
            y: floor((bounds.height - 18) / 2) - 1,
            width: textWidth,
            height: 18
        )
    }

    func apply(model: IslandBarModel) {
        currentStatus = model.status
        currentTheme = model.theme
        currentQueueCount = model.queueCount

        let theme = model.theme
        let statusColor = color(for: model.status, theme: theme)

        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        titleLabel.stringValue = model.title

        detailLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.97)
        detailLabel.stringValue = model.detail

        statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        statusLabel.textColor = statusColor.withAlphaComponent(0.98)
        statusLabel.stringValue = model.status.label

        statusDotView.layer?.backgroundColor = statusColor.cgColor
        queueBadgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        queueBadgeLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        queueBadgeLabel.stringValue = "\(model.queueCount)"
        queueBadgeView.layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        queueBadgeView.layer?.borderWidth = 1
        queueBadgeView.layer?.borderColor = NSColor(white: 0.22, alpha: 1).cgColor
        queueBadgeView.isHidden = model.queueCount == 0
        if model.queueCount > 0 {
            queueBadgeView.frame.size = NSSize(width: max(24, queueBadgeLabel.intrinsicContentSize.width + 10), height: 16)
        }

        refreshPixelStrip()
        needsLayout = true

        stopSweepAnimation()
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        let textAlpha: CGFloat = expanded ? 1.0 : 0.0
        let cornerRadius = expanded ? min(bounds.height / 2, 18) : min(bounds.height / 2, 16)

        let updates = {
            self.titleLabel.alphaValue = 0
            self.detailLabel.alphaValue = textAlpha
            self.statusLabel.alphaValue = 0
            self.statusDotView.alphaValue = 0
            self.queueBadgeView.alphaValue = self.currentQueueCount > 0 ? 1.0 : 0.0
            self.pixelStripView.alphaValue = 1.0
            self.layer?.cornerRadius = cornerRadius
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                updates()
            }
        } else {
            updates()
        }

        if !expanded {
            stopSweepAnimation()
        }
    }

    private func layoutSweepLayer() {
        guard let sweepLayer else { return }
        let sweepWidth = max(bounds.width * 0.28, 92)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sweepLayer.frame = CGRect(x: -sweepWidth, y: 0, width: sweepWidth, height: bounds.height)
        CATransaction.commit()
    }

    private func startSweepAnimation() {
        let sweepLayer: CAGradientLayer
        if let existing = self.sweepLayer {
            sweepLayer = existing
        } else {
            let created = CAGradientLayer()
            created.colors = [
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.12).cgColor,
                NSColor.clear.cgColor
            ]
            created.locations = [0, 0.5, 1]
            created.startPoint = CGPoint(x: 0, y: 0.5)
            created.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.addSublayer(created)
            self.sweepLayer = created
            sweepLayer = created
        }

        layoutSweepLayer()
        sweepLayer.isHidden = false
        guard sweepLayer.animation(forKey: "islandSweep") == nil else { return }

        let sweepWidth = sweepLayer.bounds.width
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -sweepWidth / 2
        animation.toValue = bounds.width + sweepWidth / 2
        animation.duration = 1.15
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweepLayer.add(animation, forKey: "islandSweep")
    }

    private func stopSweepAnimation() {
        sweepLayer?.removeAnimation(forKey: "islandSweep")
        sweepLayer?.isHidden = true
    }

    private func color(for status: IslandBarStatus, theme: PopoverTheme) -> NSColor {
        switch status {
        case .ready:
            return NSColor(red: 86/255, green: 192/255, blue: 255/255, alpha: 1)
        case .working, .ask, .approval:
            return NSColor(red: 86/255, green: 192/255, blue: 255/255, alpha: 1)
        case .done:
            return NSColor.white.withAlphaComponent(0.96)
        case .error:
            return NSColor(red: 1.0, green: 0.39, blue: 0.39, alpha: 1.0)
        }
    }

    private func layoutPixelStrip() {
        let spinnerSize: CGFloat = 22
        let pixelSize: CGFloat = 2.6
        pixelStripView.frame = NSRect(
            x: (isExpanded || currentQueueCount > 0) ? horizontalPadding : floor((bounds.width - spinnerSize) / 2),
            y: floor((bounds.height - spinnerSize) / 2),
            width: spinnerSize,
            height: spinnerSize
        )

        let centerX = pixelStripView.bounds.midX
        let centerY = pixelStripView.bounds.midY
        let radius = (spinnerSize - pixelSize) / 2
        for (index, pixel) in pixelViews.enumerated() {
            let progress = CGFloat(index) / CGFloat(max(pixelCount, 1))
            let angle = (-CGFloat.pi / 2) + progress * CGFloat.pi * 2
            let originX = centerX + cos(angle) * radius - pixelSize / 2
            let originY = centerY + sin(angle) * radius - pixelSize / 2
            pixel.frame = NSRect(
                x: originX,
                y: originY,
                width: pixelSize,
                height: pixelSize
            )
            pixel.layer?.cornerRadius = pixelSize / 2
        }
    }

    // 用像素点代替普通横条，尽量贴近 Vibe Island 的固定刘海气质。
    private func refreshPixelStrip() {
        let color = color(for: currentStatus, theme: currentTheme)
        let baseOpacity: Float
        switch currentStatus {
        case .ready:
            baseOpacity = 0.34
        case .done:
            baseOpacity = 0.7
        case .error:
            baseOpacity = 0.58
        case .working, .approval, .ask:
            baseOpacity = 0.56
        }

        for pixel in pixelViews {
            pixel.layer?.backgroundColor = color.cgColor
            pixel.layer?.opacity = baseOpacity
            pixel.layer?.removeAnimation(forKey: "pixelPulse")
        }

        let order = pulseOrder(for: currentStatus)
        let duration = pulseDuration(for: currentStatus)
        let stagger = pulseStagger(for: currentStatus)

        for (step, pixelIndex) in order.enumerated() where pixelIndex < pixelViews.count {
            let pixel = pixelViews[pixelIndex]
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [baseOpacity, 1.0, 0.18, baseOpacity]
            opacity.keyTimes = [0, 0.18, 0.46, 1]

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.84, 1.42, 0.92, 0.84]
            scale.keyTimes = [0, 0.18, 0.46, 1]

            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            group.duration = duration
            group.beginTime = CACurrentMediaTime() + Double(step) * stagger
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pixel.layer?.add(group, forKey: "pixelPulse")
        }
    }

    private func pulseOrder(for status: IslandBarStatus) -> [Int] {
        let indices = Array(0..<pixelCount)
        switch status {
        case .approval:
            return indices
        case .ask:
            return indices
        case .error:
            return indices.reversed()
        case .done:
            return indices
        case .working:
            return indices
        case .ready:
            return indices
        }
    }

    private func pulseDuration(for status: IslandBarStatus) -> CFTimeInterval {
        switch status {
        case .approval:
            return 0.95
        case .ask:
            return 1.05
        case .done:
            return 1.1
        case .error:
            return 0.78
        case .working:
            return 0.82
        case .ready:
            return 1.15
        }
    }

    private func pulseStagger(for status: IslandBarStatus) -> CFTimeInterval {
        switch status {
        case .approval:
            return 0.038
        case .ask:
            return 0.04
        case .done:
            return 0.034
        case .error:
            return 0.03
        case .working:
            return 0.032
        case .ready:
            return 0.04
        }
    }
}

class LilAgentsController {
    var characters: [WalkerCharacter] = []
    private var displayLink: CVDisplayLink?
    var debugWindow: NSWindow?
    private let islandEnabled = false
    private let islandCollapsedSize = NSSize(width: 176, height: 30)
    private let islandExpandedSize = NSSize(width: 420, height: 42)
    private let islandTopInset: CGFloat = 0
    private var islandWindow: IslandBarPanel?
    private var islandBarView: IslandBarView?
    private var islandTasks: [String: IslandTask] = [:]
    private var islandTaskCleanupWorkItems: [String: DispatchWorkItem] = [:]
    private var islandHideWorkItem: DispatchWorkItem?
    private var isIslandExpanded = false
    var pinnedScreenIndex: Int = -1
    private static let onboardingKey = "hasCompletedOnboarding"
    private var isHiddenForEnvironment = false

    func start() {
        let char1 = WalkerCharacter(videoName: "walk-bruce-01", name: "Bruce")
        let char2 = WalkerCharacter(videoName: "walk-jazz-01", name: "Jazz")

        // Detect available providers, then set first-run defaults
        AgentProvider.detectAvailableProviders { [weak char1, weak char2] in
            guard let char1 = char1, let char2 = char2 else { return }
            if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
                let first = AgentProvider.firstAvailable
                char1.provider = first
                char2.provider = first
            }
        }

        char1.accelStart = 3.0
        char1.fullSpeedStart = 3.75
        char1.decelStart = 8.0
        char1.walkStop = 8.5
        char1.walkAmountRange = 0.4...0.65

        char2.accelStart = 3.9
        char2.fullSpeedStart = 4.5
        char2.decelStart = 8.0
        char2.walkStop = 8.75
        char2.walkAmountRange = 0.35...0.6
        char1.yOffset = -3
        char2.yOffset = -7
        char1.characterColor = NSColor(red: 0.4, green: 0.72, blue: 0.55, alpha: 1.0)
        char2.characterColor = NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)

        char1.flipXOffset = 0
        char2.flipXOffset = -9

        char1.positionProgress = 0.3
        char2.positionProgress = 0.7

        char1.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.5...2.0)
        char2.pauseEndTime = CACurrentMediaTime() + Double.random(in: 8.0...14.0)

        char1.setup()
        char2.setup()

        characters = [char1, char2]
        characters.forEach { $0.controller = self }

        setupDebugLine()
        if islandEnabled {
            setupIslandBar()
        }
        startDisplayLink()

        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            triggerOnboarding()
        }
    }

    private func triggerOnboarding() {
        guard let bruce = characters.first else { return }
        bruce.isOnboarding = true
        // Show "hi!" bubble after a short delay so the character is visible first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            bruce.currentPhrase = "hi!"
            bruce.showingCompletion = true
            bruce.completionBubbleExpiry = CACurrentMediaTime() + 600 // stays until clicked
            bruce.showBubble(text: "hi!", isCompletion: true)
            bruce.playCompletionSound()
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        characters.forEach { $0.isOnboarding = false }
    }

    // MARK: - Debug

    private func setupDebugLine() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 2),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.red
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.moveToActiveSpace, .stationary]
        win.orderOut(nil)
        debugWindow = win
    }

    private func setupIslandBar() {
        guard islandEnabled else { return }
        let size = islandCollapsedSize
        let win = IslandBarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 30)
        win.collectionBehavior = [.moveToActiveSpace, .stationary]
        win.hidesOnDeactivate = false
        win.isFloatingPanel = true

        let contentView = IslandBarView(frame: CGRect(origin: .zero, size: size))
        contentView.onClick = { [weak self] in
            self?.openIslandCharacter()
        }

        win.contentView = contentView
        islandWindow = win
        islandBarView = contentView
        refreshIslandBar(expand: false, preferredScreen: activeScreen)
        if !isHiddenForEnvironment {
            win.orderFrontRegardless()
        }
    }

    func publishIslandEvent(from character: WalkerCharacter, taskID: String? = nil, status: IslandBarStatus, detail: String, prompt: AgentPrompt? = nil) {
        guard islandEnabled else { return }
        let resolvedTaskID = taskID ?? "character.\(character.name)"
        let cleanedDetail = compactIslandDetail(detail)
        let task = IslandTask(
            id: resolvedTaskID,
            title: "\(character.provider.displayName) · \(character.name)",
            detail: cleanedDetail.isEmpty ? status.label : cleanedDetail,
            status: status,
            theme: character.resolvedTheme,
            characterName: character.name,
            prompt: prompt,
            updatedAt: CACurrentMediaTime()
        )
        upsertIslandTask(task, expand: true, preferredScreen: character.window?.screen ?? activeScreen)
    }

    func upsertIslandTask(_ task: IslandTask, expand: Bool = true, preferredScreen: NSScreen?) {
        guard islandEnabled else { return }
        islandTaskCleanupWorkItems[task.id]?.cancel()
        islandTaskCleanupWorkItems[task.id] = nil
        islandTasks[task.id] = task
        refreshIslandBar(expand: expand, preferredScreen: preferredScreen)

        if let delay = task.status.autoClearDelay {
            scheduleIslandTaskRemoval(taskID: task.id, after: delay)
        }
    }

    func removeIslandTask(taskID: String, preferredScreen: NSScreen? = nil) {
        guard islandEnabled else { return }
        islandTaskCleanupWorkItems[taskID]?.cancel()
        islandTaskCleanupWorkItems[taskID] = nil
        islandTasks.removeValue(forKey: taskID)
        refreshIslandBar(expand: false, preferredScreen: preferredScreen)
    }

    private func scheduleIslandTaskRemoval(taskID: String, after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.islandTaskCleanupWorkItems[taskID] = nil
            self?.islandTasks.removeValue(forKey: taskID)
            self?.refreshIslandBar(expand: false, preferredScreen: self?.activeScreen)
        }
        islandTaskCleanupWorkItems[taskID]?.cancel()
        islandTaskCleanupWorkItems[taskID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func refreshIslandBar(expand: Bool, preferredScreen: NSScreen?) {
        guard islandEnabled else { return }
        guard let islandBarView, let islandWindow else { return }

        let tasks = sortedIslandTasks()
        let topTask = tasks.first
        let queueCount = tasks.count
        let theme = topTask?.theme ?? PopoverTheme.current.withCustomFont()
        let status = topTask?.status ?? .ready
        let detail = topTask?.detail ?? "One notch."
        let screen = preferredScreen ?? screen(for: topTask) ?? activeScreen

        islandBarView.apply(model: IslandBarModel(
            title: topTask?.title ?? "lil agents",
            detail: detail,
            status: status,
            theme: theme,
            queueCount: queueCount
        ))

        islandHideWorkItem?.cancel()
        let shouldExpand = topTask != nil && (expand || topTask?.status == .approval || topTask?.status == .ask)
        if topTask != nil {
            setIslandExpanded(shouldExpand, on: screen, animated: true)
            scheduleIslandCollapse(for: status)
        } else {
            setIslandExpanded(false, on: screen, animated: true)
        }

        if !isHiddenForEnvironment {
            islandWindow.orderFrontRegardless()
        }
    }

    private func sortedIslandTasks() -> [IslandTask] {
        islandTasks.values.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority > rhs.status.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func scheduleIslandCollapse(for status: IslandBarStatus) {
        guard islandEnabled else { return }
        let delay: TimeInterval
        switch status {
        case .approval, .ask:
            delay = 4.2
        case .working:
            delay = 2.6
        case .done, .error, .ready:
            delay = 1.8
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseIslandBar()
        }
        islandHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func compactIslandDetail(_ text: String) -> String {
        let singleLine = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard singleLine.count > 72 else { return singleLine }
        return String(singleLine.prefix(69)) + "..."
    }

    private func islandFrame(for size: NSSize, on screen: NSScreen?) -> CGRect? {
        guard let screen else { return nil }
        let x = floor(screen.frame.midX - size.width / 2)
        let y = floor(screen.frame.maxY - size.height - islandTopInset)
        return CGRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func setIslandExpanded(_ expanded: Bool, on screen: NSScreen?, animated: Bool) {
        guard islandEnabled else { return }
        guard let islandWindow, let islandBarView else { return }
        isIslandExpanded = expanded
        let size = expanded ? islandExpandedSize : islandCollapsedSize
        guard let frame = islandFrame(for: size, on: screen) else { return }

        islandBarView.setExpanded(expanded, animated: animated)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                islandWindow.animator().setFrame(frame, display: true)
            }
        } else {
            islandWindow.setFrame(frame, display: true)
        }
    }

    private func collapseIslandBar() {
        guard islandEnabled else { return }
        islandHideWorkItem?.cancel()
        islandHideWorkItem = nil
        setIslandExpanded(false, on: screen(for: sortedIslandTasks().first) ?? activeScreen, animated: true)
    }

    private func openIslandCharacter() {
        guard islandEnabled else { return }
        // 暂时关闭灵动岛到 popover 的入口，避免再次触发弹框链路。
    }

    private func character(named name: String?) -> WalkerCharacter? {
        guard let name else { return nil }
        return characters.first(where: { $0.name == name })
    }

    private func screen(for task: IslandTask?) -> NSScreen? {
        guard let task, let character = character(named: task.characterName) else { return nil }
        return character.window?.screen
    }

    private func updateDebugLine(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        guard let win = debugWindow, win.isVisible else { return }
        win.setFrame(CGRect(x: dockX, y: dockTopY, width: dockWidth, height: 2), display: true)
    }

    // MARK: - Dock Geometry

    private func getDockIconArea(screenWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
        let slotWidth = tileSize * 1.25

        var persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        var persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0

        // Fallback for defaults reading issues
        if persistentApps == 0 && persistentOthers == 0 {
            persistentApps = 5
            persistentOthers = 3
        }

        let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
        let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12.0
        var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth

        // Small fudge factor for dock edge padding
        dockWidth *= 1.15
        let dockX = (screenWidth - dockWidth) / 2.0
        return (dockX, dockWidth)
    }

    private func dockAutohideEnabled() -> Bool {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        return dockDefaults?.bool(forKey: "autohide") ?? false
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let controller = Unmanaged<LilAgentsController>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
                                       Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    var activeScreen: NSScreen? {
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return NSScreen.screens[pinnedScreenIndex]
        }
        // Prefer the screen that currently shows the dock (bottom inset in visibleFrame).
        // NSScreen.main changes with keyboard focus and must NOT be used here — clicking a
        // secondary display switches NSScreen.main to that display, causing characters on
        // the dock screen to be incorrectly hidden.
        if let dockScreen = NSScreen.screens.first(where: { screenHasDock($0) }) {
            return dockScreen
        }
        // Dock is auto-hidden: fall back to the primary display, identified as the screen
        // whose menu bar reserves space at the top (visibleFrame.maxY < frame.maxY).
        if let primaryScreen = NSScreen.screens.first(where: { $0.visibleFrame.maxY < $0.frame.maxY }) {
            return primaryScreen
        }
        return NSScreen.screens.first
    }

    private func screenHasDock(_ screen: NSScreen) -> Bool {
        DockVisibility.screenHasVisibleDockReservedArea(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }

    private func shouldShowCharacters(on screen: NSScreen) -> Bool {
        // User explicitly pinned to this screen — always show
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return true
        }
        return DockVisibility.shouldShowCharacters(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            isMainScreen: screen == NSScreen.main,
            dockAutohideEnabled: dockAutohideEnabled()
        )
    }

    @discardableResult
    private func updateEnvironmentVisibility(for screen: NSScreen) -> Bool {
        let shouldShow = shouldShowCharacters(on: screen)
        guard shouldShow != !isHiddenForEnvironment else { return shouldShow }

        isHiddenForEnvironment = !shouldShow

        if shouldShow {
            characters.forEach { $0.showForEnvironmentIfNeeded() }
            if islandEnabled {
                setIslandExpanded(isIslandExpanded, on: screen, animated: false)
                islandWindow?.orderFrontRegardless()
            }
        } else {
            debugWindow?.orderOut(nil)
            islandWindow?.orderOut(nil)
            characters.forEach { $0.hideForEnvironment() }
        }

        return shouldShow
    }

    func tick() {
        guard let screen = activeScreen else { return }
        guard updateEnvironmentVisibility(for: screen) else { return }

        let screenWidth = screen.frame.width
        let dockX: CGFloat
        let dockWidth: CGFloat
        let dockTopY: CGFloat

        // Dock is on this screen — constrain to dock area
        (dockX, dockWidth) = getDockIconArea(screenWidth: screenWidth)
        dockTopY = screen.visibleFrame.origin.y

        updateDebugLine(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)

        let activeChars = characters.filter { char in
            guard let window = char.window else { return false }
            return window.isVisible && char.isManuallyVisible
        }

        for char in activeChars {
            char.update(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
        }

        let sorted = activeChars.sorted { $0.positionProgress < $1.positionProgress }
        for (i, char) in sorted.enumerated() {
            char.window?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + i)
        }

        if islandEnabled, islandWindow?.isVisible == true {
            setIslandExpanded(isIslandExpanded, on: screen, animated: false)
        }
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
