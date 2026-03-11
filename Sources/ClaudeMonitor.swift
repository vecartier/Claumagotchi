import Foundation
import Combine
import AppKit

// MARK: - State

enum ClaudeState: Equatable {
    case thinking
    case finished
    case needsYou

    var label: String {
        switch self {
        case .thinking: "THINKING..."
        case .finished: "DONE!"
        case .needsYou: "NEEDS YOU!"
        }
    }

    var needsAttention: Bool { self == .needsYou }
    var canGoToConvo: Bool { self == .finished }
}

// MARK: - Pending Permission

struct PendingPermission: Equatable {
    let id: String
    let tool: String
    let summary: String
}

// MARK: - Monitor

final class ClaudeMonitor: ObservableObject {
    static let eventsFile = "/tmp/clawgotchi-events.jsonl"
    static let pendingFile = "/tmp/clawgotchi-pending.json"
    static let responseFile = "/tmp/clawgotchi-response.json"

    @Published var state: ClaudeState = .finished
    @Published var pendingPermission: PendingPermission?
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var autoAccept: Bool {
        didSet { UserDefaults.standard.set(autoAccept, forKey: "autoAccept") }
    }

    /// True when a permission has been requested and user hasn't acted yet.
    /// This is the source of truth — never cleared by timeouts or external events.
    private var awaitingUserAction = false

    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var idleTimer: Timer?

    init() {
        soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        autoAccept = UserDefaults.standard.object(forKey: "autoAccept") as? Bool ?? false
        setupFileWatcher()
    }

    deinit {
        source?.cancel()
        try? fileHandle?.close()
        idleTimer?.invalidate()
    }

    // MARK: Actions

    func respondToPermission(allow: Bool) {
        guard let pending = pendingPermission else {
            // Even without pending data, clear the awaiting flag
            awaitingUserAction = false
            state = allow ? .thinking : .finished
            return
        }
        let response: [String: Any] = ["id": pending.id, "decision": allow ? "allow" : "deny"]
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            try? data.write(to: URL(fileURLWithPath: Self.responseFile))
        }
        pendingPermission = nil
        awaitingUserAction = false
        state = allow ? .thinking : .finished
    }

    func goToConversation() {
        idleTimer?.invalidate()
        pendingPermission = nil
        awaitingUserAction = false
        state = .finished
        activateTerminal()
    }

    private func activateTerminal() {
        let ids = [
            "com.apple.Terminal", "com.googlecode.iterm2",
            "dev.warp.Warp-Stable", "io.alacritty",
            "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        ]
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, ids.contains(bid) {
                app.activate()
                return
            }
        }
    }

    // MARK: File Watcher

    private func setupFileWatcher() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.eventsFile) {
            fm.createFile(atPath: Self.eventsFile, contents: nil)
        }
        guard let fh = FileHandle(forReadingAtPath: Self.eventsFile) else { return }
        fh.seekToEndOfFile()
        self.fileHandle = fh

        let fd = open(Self.eventsFile, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .main
        )
        source.setEventHandler { [weak self] in self?.readNewEvents() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func readNewEvents() {
        guard let fh = fileHandle else { return }
        let data = fh.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") { processEvent(String(line)) }
    }

    private func processEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["event"] as? String else { return }

        // Permission ALWAYS wins
        if type == "permission" {
            idleTimer?.invalidate()
            loadPendingPermission()
            if autoAccept {
                // Auto-accept after a short delay to let pending file load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.respondToPermission(allow: true)
                }
            } else {
                awaitingUserAction = true
                state = .needsYou
                playAlert()
            }
            return
        }
        if type == "notification", event["type"] as? String == "permission_prompt" {
            idleTimer?.invalidate()
            loadPendingPermission()
            if autoAccept {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.respondToPermission(allow: true)
                }
            } else {
                awaitingUserAction = true
                state = .needsYou
                playAlert()
            }
            return
        }
        if type == "permission_timeout" {
            // Hook timed out but keep showing in UI — user must act on it.
            return
        }

        // Awaiting user action -> nothing else changes display
        guard !awaitingUserAction else { return }

        idleTimer?.invalidate()

        switch type {
        case "pre_tool", "post_tool", "post_tool_error":
            state = .thinking
        case "stop":
            state = .finished
            playDoneChime()
            startIdleTimer(interval: 60)
        case "session_start":
            state = .thinking
        case "session_end":
            if state == .thinking {
                state = .finished
            }
        default:
            break
        }
    }

    // MARK: Pending Permission

    private func loadPendingPermission(retries: Int = 5) {
        guard let data = FileManager.default.contents(atPath: Self.pendingFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.loadPendingPermission(retries: retries - 1)
                }
            }
            return
        }
        let tool = json["tool"] as? String ?? ""
        let input = json["input"] as? [String: Any] ?? [:]
        pendingPermission = PendingPermission(
            id: id, tool: tool,
            summary: Self.extractSummary(tool: tool, input: input)
        )
    }

    private static func extractSummary(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            let t = String(cmd.prefix(50))
            return t.count < cmd.count ? t + "..." : t
        case "Write", "Read", "Edit", "Glob":
            let path = input["file_path"] as? String ?? input["pattern"] as? String ?? ""
            return URL(fileURLWithPath: path).lastPathComponent
        case "Grep":  return input["pattern"] as? String ?? "search"
        case "Agent": return input["description"] as? String ?? "sub-agent"
        default:      return tool.lowercased()
        }
    }

    // MARK: Timers & Sound

    private func startIdleTimer(interval: TimeInterval) {
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.pendingPermission == nil else { return }
            self.state = .finished
        }
    }

    private func playAlert() {
        guard soundEnabled else { return }
        NSSound(named: "Ping")?.play()
    }

    private func playDoneChime() {
        guard soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }
}
