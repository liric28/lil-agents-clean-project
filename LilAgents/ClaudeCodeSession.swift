import Foundation

/// Session that launches the `claude` CLI with environment variables set to route
/// through the free-claude-code proxy (127.0.0.1:8082).
class ClaudeCodeSession: AgentSession {
    /// Path to free-claude-code project.
    private static let freeClaudeCodePath = "/Users/lipan/free-claude-code"

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private var currentResponseText = ""
    private var pendingMessages: [String] = []
    private(set) var isRunning = false
    private(set) var isBusy = false
    private static var binaryPath: String?

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    var history: [AgentMessage] = []

    // MARK: - Lifecycle

    func start() {
        if let cached = Self.binaryPath {
            launchProcess(binaryPath: cached)
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "claude", fallbackPaths: [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                let msg = "Claude CLI not found.\\n\\n\(AgentProvider.claudeCode.installInstructions)"
                self?.onError?(msg)
                self?.history.append(AgentMessage(role: .error, text: msg))
                return
            }
            Self.binaryPath = binaryPath
            self.launchProcess(binaryPath: binaryPath)
        }
    }

    private func launchProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        // Route through free-claude-code proxy via environment variables
        proc.arguments = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions"
        ]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        proc.environment = Self.claudeProcessEnvironment()

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isBusy = false
                self?.onProcessExit?()
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processOutput(text)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.onError?(text)
                }
            }
        }

        do {
            try proc.run()
            process = proc
            inputPipe = inPipe
            outputPipe = outPipe
            errorPipe = errPipe
            isRunning = true
            let pending = pendingMessages
            pendingMessages = []
            for msg in pending {
                writeMessage(msg, to: inPipe)
            }
        } catch {
            let msg = "Failed to launch Claude CLI.\\n\\n\(AgentProvider.claudeCode.installInstructions)\\n\\nError: \(error.localizedDescription)"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))
        }
    }

    func send(message: String) {
        guard isRunning, let pipe = inputPipe else {
            pendingMessages.append(message)
            return
        }
        writeMessage(message, to: pipe)
    }

    private func writeMessage(_ message: String, to pipe: Pipe) {
        isBusy = true
        currentResponseText = ""
        history.append(AgentMessage(role: .user, text: message))

        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": message
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8),
              let lineData = (jsonStr + "\n").data(using: .utf8) else { return }
        try? pipe.fileHandleForWriting.write(contentsOf: lineData)
    }

    func terminate() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        isRunning = false
        isBusy = false
        pendingMessages.removeAll()
    }

    // MARK: - NDJSON Parsing

    private func processOutput(_ text: String) {
        lineBuffer += text
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            if !line.isEmpty {
                parseLine(line)
            }
        }
    }

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""

        switch type {
        case "system":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "init" {
                onSessionReady?()
            }

        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        currentResponseText += text
                        onText?(text)
                    } else if blockType == "tool_use" {
                        let toolName = block["name"] as? String ?? "Tool"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let summary = formatToolSummary(toolName: toolName, input: input)
                        history.append(AgentMessage(role: .toolUse, text: "\(toolName): \(summary)"))
                        onToolUse?(toolName, input)
                    }
                }
            }

        case "user":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result" {
                        let isError = block["is_error"] as? Bool ?? false
                        var summary = ""
                        if let resultInfo = json["tool_use_result"] as? [String: Any] {
                            if let text = resultInfo["type"] as? String, text == "text" {
                                if let file = resultInfo["file"] as? [String: Any],
                                   let path = file["filePath"] as? String {
                                    let lines = file["totalLines"] as? Int ?? 0
                                    summary = "\(path) (\(lines) lines)"
                                }
                            }
                        } else if let resultStr = json["tool_use_result"] as? String {
                            summary = String(resultStr.prefix(80))
                        }
                        if summary.isEmpty {
                            if let contentStr = block["content"] as? String {
                                summary = String(contentStr.prefix(80))
                            }
                        }
                        history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
                        onToolResult?(summary, isError)
                    }
                }
            }

        case "result":
            isBusy = false
            let finalText: String
            if let result = json["result"] as? String, !result.isEmpty {
                finalText = result
            } else if !currentResponseText.isEmpty {
                finalText = currentResponseText
            } else {
                finalText = ""
            }
            if !finalText.isEmpty {
                history.append(AgentMessage(role: .assistant, text: finalText))
            }
            currentResponseText = ""
            onTurnComplete?()

        default:
            break
        }
    }

    private func formatToolSummary(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Edit", "Write":
            return input["file_path"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        case "Glob":
            if let pattern = input["pattern"] as? String { return pattern }
            return input["path"] as? String ?? ""
        default:
            let keys = Array(input.keys).joined(separator: ", ")
            return keys.isEmpty ? toolName : "\(toolName)(\(keys))"
        }
    }

    // MARK: - Environment

    /// Injects proxy environment variables for free-claude-code routing.
    private static func claudeProcessEnvironment() -> [String: String] {
        // Use ShellEnvironment to get proper PATH with all bin directories
        var env = ShellEnvironment.processEnvironment()
        // Route Claude through free-claude-code proxy
        env["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:8082"
        // Read auth token from .env if present
        if let token = Self.readAuthToken(), !token.isEmpty {
            env["ANTHROPIC_AUTH_TOKEN"] = token
        }
        return env
    }

    /// Reads ANTHROPIC_AUTH_TOKEN from free-claude-code/.env
    private static func readAuthToken() -> String? {
        let envPath = "\(freeClaudeCodePath)/.env"
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return nil
        }
        // Parse ANTHROPIC_AUTH_TOKEN=VALUE (supports quoted values)
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ANTHROPIC_AUTH_TOKEN=") {
                var value = String(trimmed.dropFirst("ANTHROPIC_AUTH_TOKEN=".count))
                // Strip quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                } else if value.hasPrefix("'") && value.hasSuffix("'") {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
