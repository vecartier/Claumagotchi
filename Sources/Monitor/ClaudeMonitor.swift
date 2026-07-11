import Foundation
import Combine
import AppKit
import ApplicationServices
import AVFoundation
import Speech
import HotKey
import Carbon.HIToolbox

// MARK: - State

enum ClaudeState: Equatable {
    case idle
    case working
    case done
    case error
    case approveQuestion   // APPROVE?
    case needsInput        // NEEDS INPUT
    case listening         // Recording voice
    case speaking          // TTS reading aloud

    var label: String {
        switch self {
        case .idle: "ZZZ..."
        case .working: "WORKING"
        case .done: "DONE!"
        case .error: "ERROR"
        case .approveQuestion: "APPROVE?"
        case .needsInput: "INPUT?"
        case .listening: "LISTENING"
        case .speaking: "SPEAKING"
        }
    }

    /// State priority — higher number wins when resolving multiple concurrent sessions.
    var priority: Int {
        switch self {
        case .error: return 7
        case .approveQuestion: return 6
        case .needsInput: return 5
        case .listening: return 4
        case .speaking: return 3
        case .working: return 2
        case .done: return 1
        case .idle: return 0
        }
    }

    var needsAttention: Bool { self == .approveQuestion }
    var canGoToConvo: Bool { self == .done }
}

// MARK: - Monitor

@MainActor
final class ClaudeMonitor: ObservableObject {
    static let ipcDir = NSHomeDirectory() + "/.claude/cc-beeper"

    /// Auto-approve response sent back to Claude Code for YOLO/allowed tools.
    static let autoApproveResponse: [String: Any] = [
        "_send_immediately": true,
        "hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": ["behavior": "allow"]
        ]
    ]

    // MARK: - Published State

    @Published var state: ClaudeState = .idle
    @Published var pendingPermission: PendingPermission?
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var currentPreset: PermissionPreset = .cautious {
        didSet {
            guard oldValue != currentPreset else { return }
            do {
                try PermissionPresetWriter.applyPreset(currentPreset)
            } catch {
                currentPreset = oldValue
            }
        }
    }
    @Published var isSettingsMalformed: Bool = false
    @Published var widgetSize: WidgetSize {
        didSet { UserDefaults.standard.set(widgetSize.rawValue, forKey: "widgetSize") }
    }
    @Published var vibrationEnabled: Bool {
        didSet { UserDefaults.standard.set(vibrationEnabled, forKey: "vibrationEnabled") }
    }
    @Published var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: "isMuted")
            if isMuted && ttsService.isSpeaking {
                ttsService.stopSpeaking()
            }
        }
    }
    @Published var sessionCount: Int = 0
    @Published var errorDetail: String? = nil
    @Published var inputMessage: String? = nil
    @Published var authFlashMessage: String? = nil
    @Published var idleStartTime: Date? = nil
    @Published var isActive: Bool = true {
        didSet {
            UserDefaults.standard.set(isActive, forKey: "isActive")
            if isActive {
                httpServer.start { [weak self] payload in
                    guard let self else { return nil }
                    return self.handleHookPayload(payload)
                }
                setupGlobalHotkeys()
            } else {
                voiceService.stopIfRecording()
                ttsService.stopSpeaking()
                httpServer.stop()
                idleWork?.cancel()
                carbonHotKeys.removeAll()
                if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
                state = .idle
                idleStartTime = Date()
                pendingPermission = nil
                awaitingUserAction = false
            }
        }
    }
    @Published var thinkingStartTime: Date? = nil
    @Published var currentTool: String? = nil
    @Published var lastSummary: String? = nil
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isSpeaking: Bool = false

    let voiceService = VoiceService()
    let ttsService = TTSService()
    let voiceCommandService = VoiceCommandService()

    @Published var clapDictationEnabled: Bool = UserDefaults.standard.bool(forKey: "voiceCommandsEnabled") {
        didSet { voiceCommandService.enabled = clapDictationEnabled }
    }

    @Published var voiceOver: Bool = false {
        didSet { UserDefaults.standard.set(voiceOver, forKey: "voiceOver") }
    }
    @Published var ttsProvider: String = "kokoro" {
        didSet { UserDefaults.standard.set(ttsProvider, forKey: "ttsProvider") }
    }
    @Published var appleVoiceId: String = "" {
        didSet {
            UserDefaults.standard.set(appleVoiceId, forKey: "appleVoiceId")
            ttsService.setAppleVoice(appleVoiceId)
        }
    }
    @Published var autoLanguageRouting: Bool = true {
        didSet {
            UserDefaults.standard.set(autoLanguageRouting, forKey: "autoLanguageRouting")
            ttsService.setAutoLanguageRouting(autoLanguageRouting)
        }
    }

    // MARK: - Hotkey Bindings

    @Published var hotkeyAccept: String = "A" {
        didSet { UserDefaults.standard.set(hotkeyAccept, forKey: "hotkeyChar_accept"); setupGlobalHotkeys() }
    }
    @Published var hotkeyDeny: String = "D" {
        didSet { UserDefaults.standard.set(hotkeyDeny, forKey: "hotkeyChar_deny"); setupGlobalHotkeys() }
    }
    @Published var hotkeyVoice: String = "R" {
        didSet { UserDefaults.standard.set(hotkeyVoice, forKey: "hotkeyChar_voice"); setupGlobalHotkeys() }
    }
    @Published var hotkeyTerminal: String = "T" {
        didSet { UserDefaults.standard.set(hotkeyTerminal, forKey: "hotkeyChar_terminal"); setupGlobalHotkeys() }
    }
    @Published var hotkeyMute: String = "M" {
        didSet { UserDefaults.standard.set(hotkeyMute, forKey: "hotkeyChar_mute"); setupGlobalHotkeys() }
    }

    @Published var whisperModelSize: String = "small" {
        didSet { UserDefaults.standard.set(whisperModelSize, forKey: "whisperModelSize") }
    }
    @Published var kokoroVoice: String = "bm_daniel" {
        didSet {
            UserDefaults.standard.set(kokoroVoice, forKey: "kokoroVoice")
            ttsService.setKokoroVoice(kokoroVoice)
        }
    }
    @Published var kokoroLangCode: String = "b" {
        didSet {
            UserDefaults.standard.set(kokoroLangCode, forKey: "kokoroLangCode")
            ttsService.setKokoroLangCode(kokoroLangCode)
            if !KokoroVoiceCatalog.isVoiceValid(kokoroVoice, for: kokoroLangCode) {
                kokoroVoice = KokoroVoiceCatalog.defaultVoice(for: kokoroLangCode)
            }
        }
    }

    // MARK: - Internal State (accessed by extensions in separate files)

    var awaitingUserAction = false
    var sessionStates: [String: ClaudeState] = [:]
    var sessionLastSeen: [String: Date] = [:]
    let httpServer = HTTPHookServer()
    var idleWork: DispatchWorkItem?
    var doneDebounceWork: DispatchWorkItem?
    var lastPruneTime: Date = .distantPast
    var localKeyMonitor: Any?
    var carbonHotKeys: [Any] = []
    var cancellables = Set<AnyCancellable>()

    var elapsedSeconds: Int {
        guard let start = thinkingStartTime else { return 0 }
        return Int(Date().timeIntervalSince(start))
    }

    var menuBarIconState: BeeperIconState {
        if !isActive { return .hidden }
        if !CCBeeperApp.isMainWindowVisible() {
            if isRecording { return .recording }
            if ttsService.isSpeaking { return .speaking }
        }
        if currentPreset == .yolo { return .yolo }
        if state.needsAttention { return .attention }
        return .normal
    }

    // MARK: - Init

    @Published var servicesStarted: Bool = false

    init() {
        soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        vibrationEnabled = UserDefaults.standard.object(forKey: "vibrationEnabled") as? Bool ?? true
        isMuted = UserDefaults.standard.bool(forKey: "isMuted")
        widgetSize = WidgetSize(rawValue: UserDefaults.standard.string(forKey: "widgetSize") ?? "") ?? .large
        currentPreset = PermissionPresetWriter.readCurrentPreset()
        isSettingsMalformed = PermissionPresetWriter.isSettingsMalformed()
        PermissionPresetWriter.migrateLegacyFields()
        // Migrate legacy voiceOver key
        if UserDefaults.standard.object(forKey: "voiceOver") == nil,
           let legacy = UserDefaults.standard.object(forKey: "autoSpeak") as? Bool {
            UserDefaults.standard.set(legacy, forKey: "voiceOver")
            UserDefaults.standard.removeObject(forKey: "autoSpeak")
        }
        voiceOver = UserDefaults.standard.bool(forKey: "voiceOver")
        ttsProvider = UserDefaults.standard.string(forKey: "ttsProvider") ?? "kokoro"
        appleVoiceId = UserDefaults.standard.string(forKey: "appleVoiceId") ?? ""
        autoLanguageRouting = UserDefaults.standard.object(forKey: "autoLanguageRouting") as? Bool ?? true
        kokoroLangCode = UserDefaults.standard.string(forKey: "kokoroLangCode") ?? "b"
        kokoroVoice = UserDefaults.standard.string(forKey: "kokoroVoice") ?? "bm_daniel"
        whisperModelSize = UserDefaults.standard.string(forKey: "whisperModelSize") ?? "small"
        migrateHotkeyDefaults()
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_accept") { hotkeyAccept = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_deny") { hotkeyDeny = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_voice") { hotkeyVoice = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_terminal") { hotkeyTerminal = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_mute") { hotkeyMute = v }
        isActive = UserDefaults.standard.object(forKey: "isActive") as? Bool ?? true
        voiceService.ttsService = ttsService
        ttsService.setAppleVoice(appleVoiceId)
        ttsService.setAutoLanguageRouting(autoLanguageRouting)
        wireVoiceStateBindings()
        wireVoiceCommands()

        // Only start services if onboarding is already complete
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            startServices()
        }
    }

    /// Re-read every onboarding-written preference from UserDefaults into the
    /// live @Published properties, so their didSet side effects (global hotkey
    /// registration, Kokoro voice binding, etc.) fire with the freshly chosen
    /// values. Called after the onboarding flow finishes.
    func reloadFromDefaults() {
        widgetSize = WidgetSize(rawValue: UserDefaults.standard.string(forKey: "widgetSize") ?? "") ?? .large
        currentPreset = PermissionPresetWriter.readCurrentPreset()
        kokoroLangCode = UserDefaults.standard.string(forKey: "kokoroLangCode") ?? "b"
        kokoroVoice = UserDefaults.standard.string(forKey: "kokoroVoice") ?? "bm_daniel"
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_accept") { hotkeyAccept = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_deny") { hotkeyDeny = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_voice") { hotkeyVoice = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_terminal") { hotkeyTerminal = v }
        if let v = UserDefaults.standard.string(forKey: "hotkeyChar_mute") { hotkeyMute = v }
    }

    /// Start all background services — called after onboarding completes or on launch if already set up.
    func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        ensureIPCDir()
        httpServer.start { [weak self] payload in
            guard let self else { return nil }
            return self.handleHookPayload(payload)
        }
        setupGlobalHotkeys()
        idleStartTime = Date()
        preWarmWhisper()
        launchKokoro()
        // Delay permission check so SwiftUI view is observing before we set the value
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    // MARK: - Permission Health Check

    @Published var missingPermissions: [String] = []

    func checkPermissions() {
        var missing: [String] = []
        if !AXIsProcessTrusted() {
            missing.append("Accessibility")
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            missing.append("Microphone")
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            missing.append("Speech Recognition")
        }
        missingPermissions = missing
    }

    deinit {
        ttsService.stopSpeaking()
        ttsService.shutdownKokoro()
    }

    // MARK: - Actions

    func goToConversation() {
        FocusService.focusClaudeSession()
    }

    func triggerSummary() {
        guard !isMuted, let text = lastSummary, !text.isEmpty, !ttsService.isSpeaking else { return }
        Task { await ttsService.speakSummary(text, provider: ttsProvider) }
    }

    func playAlert() {
        guard soundEnabled, !isMuted else { return }
        NSSound(named: "Ping")?.play()
    }

    func playDoneChime() {
        guard soundEnabled, !isMuted else { return }
        NSSound(named: "Pop")?.play()
    }

    func startIdleTimer(interval: TimeInterval) {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Clear stale permission state if the underlying HTTP connection is gone
                // (Claude Code was killed without sending a Stop hook).
                if self.pendingPermission != nil && self.httpServer.pendingPermissionConnections.isEmpty {
                    self.awaitingUserAction = false
                    self.pendingPermission = nil
                }
                guard self.pendingPermission == nil else { return }
                // No hook activity for the full interval — treat any lingering
                // sessions as stale (SessionEnd hook was removed in v7.0, so
                // sessions at .done/.error never get cleaned up otherwise).
                self.sessionStates.removeAll()
                self.sessionLastSeen.removeAll()
                self.sessionCount = 0
                self.state = .idle
                self.idleStartTime = Date()
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    // MARK: - Private Setup

    private func ensureIPCDir() {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: Self.ipcDir, isDirectory: &isDir) || !isDir.boolValue {
            try? fm.createDirectory(atPath: Self.ipcDir, withIntermediateDirectories: true)
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.ipcDir)
    }

    private func wireVoiceCommands() {
        voiceCommandService.onDoubleClap = { [weak self] in
            self?.voiceService.toggle()
        }
        // Forward VoiceService's audio buffer to clap detector during recording
        // (VoiceService's engine takes over the mic, so clap detector's own engine
        // can't hear — pipe the buffer through instead)
        voiceService.onAudioBuffer = { [weak self] buffer in
            self?.voiceCommandService.detectClap(buffer: buffer)
        }
        if voiceCommandService.enabled {
            voiceCommandService.startListening()
        }
    }

    private func wireVoiceStateBindings() {
        voiceService.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                guard let self else { return }
                self.isRecording = recording
                if recording {
                    self.state = .listening
                } else if self.state == .listening {
                    // Let aggregate resolve — don't blindly set .done, which
                    // could hide a pending permission prompt (AUDIT-FIX).
                    self.updateAggregateState()
                    if self.state == .listening || self.state == .idle {
                        self.state = .done
                        self.startIdleTimer(interval: 180)
                    }
                }
            }
            .store(in: &cancellables)
        ttsService.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                guard let self else { return }
                self.isSpeaking = speaking
                if speaking {
                    self.state = .speaking
                } else if self.state == .speaking {
                    self.updateAggregateState()
                    if self.state == .speaking || self.state == .idle {
                        self.state = .done
                        self.startIdleTimer(interval: 180)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func preWarmWhisper() {
        Task {
            guard WhisperService.modelsDownloaded else { return }
            do {
                let size = WhisperModelSize(rawValue: self.whisperModelSize) ?? .small
                try await WhisperService.shared.initialize(size: size)
            } catch {
                let line = "[\(Date())] Whisper pre-warm failed: \(error)\n"
                let logPath = Self.ipcDir + "/voice.log"
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(line.data(using: .utf8)!)
                    fh.closeFile()
                }
            }
        }
    }

    private func launchKokoro() {
        ttsService.onKokoroReady = { [weak self] in
            guard let self else { return }
            self.ttsService.setKokoroLangCode(self.kokoroLangCode)
            self.ttsService.setKokoroVoice(self.kokoroVoice)
        }
        ttsService.launchKokoro()
    }
}
