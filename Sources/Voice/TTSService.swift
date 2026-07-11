import Foundation
import AVFoundation
import NaturalLanguage
import os.log

final class TTSService: ObservableObject, @unchecked Sendable {

    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: TTSSpeechDelegate?

    // Playback
    private var audioPlayer: AVAudioPlayer?
    private var playerDelegate: TTSPlaybackDelegate?

    // Preview playback — isolated from the main speech pipeline so the
    // menu bar icon and LCD widget stay idle during voice auditioning.
    private var previewPlayer: AVAudioPlayer?
    private var previewDelegate: TTSPlaybackDelegate?

    // Kokoro state
    private var kokoroAvailable: Bool = false
    private var currentVoice: String = "bm_daniel"
    private var currentLangCode: String = "b"
    var onKokoroReady: (() -> Void)?

    // Apple state
    private var currentAppleVoiceId: String = ""   // empty = automatic (legacy Ava / language match)
    private var autoLanguageRouting: Bool = true
    private let previewSynthesizer = AVSpeechSynthesizer()

    // MARK: - Logging

    private static let logger = Logger(subsystem: "com.vecartier.cc-beeper", category: "tts")

    func log(_ msg: String) {
        Self.logger.info("\(msg, privacy: .public)")
        // Also write to file for diagnostics (os.Logger info not persisted)
        let path = NSHomeDirectory() + "/.claude/cc-beeper/tts.log"
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        if let d = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile(); fh.write(d); try? fh.close()
            } else {
                try? d.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: - Public API

    /// Speak the given text directly. Returns what was spoken.
    func speakSummary(_ text: String, provider: String = "apple") async -> String {
        await MainActor.run { speak(text, provider: provider) }
        return text
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        previewPlayer?.stop()
        previewPlayer = nil
        isSpeaking = false
    }

    /// Preview a Kokoro voice from Settings. Runs on an isolated audio player
    /// and deliberately does NOT touch `isSpeaking`, so the menu bar icon and
    /// LCD widget stay idle while auditioning voices.
    func previewKokoroVoice(text: String, voice: String) {
        guard !text.isEmpty else { return }
        log("Kokoro: preview(\(voice)): \(text.prefix(80))")
        previewPlayer?.stop()
        previewPlayer = nil
        Task { [weak self] in
            do {
                let data = try await KokoroService.shared.synthesize(text: text, voice: voice)
                await MainActor.run {
                    guard let self else { return }
                    do {
                        let player = try AVAudioPlayer(data: data, fileTypeHint: "wav")
                        self.previewDelegate = TTSPlaybackDelegate { [weak self] in
                            DispatchQueue.main.async {
                                self?.previewPlayer = nil
                                self?.log("Kokoro: preview finished")
                            }
                        }
                        player.delegate = self.previewDelegate
                        self.previewPlayer = player
                        player.play()
                    } catch {
                        self.log("Kokoro: preview playback error — \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run {
                    self?.log("Kokoro: preview synthesis failed — \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Kokoro Lifecycle

    func launchKokoro() {
        guard KokoroService.modelsDownloaded else {
            log("Kokoro: models not downloaded — falling back to Apple voice")
            kokoroAvailable = false
            return
        }
        kokoroAvailable = true
        let voice = currentVoice
        // Warm up the model in the background so first speech is fast
        Task { [weak self] in
            do {
                try await KokoroService.shared.initialize(defaultVoice: voice)
                await MainActor.run {
                    self?.log("Kokoro: ready (native Swift)")
                    self?.onKokoroReady?()
                }
            } catch {
                await MainActor.run {
                    self?.log("Kokoro: initialize failed — \(error.localizedDescription)")
                    self?.kokoroAvailable = false
                }
            }
        }
    }

    func setKokoroVoice(_ voice: String) {
        currentVoice = voice
        log("Kokoro: voice set to \(voice)")
        Task { await KokoroService.shared.setDefaultVoice(voice) }
    }

    func setKokoroLangCode(_ code: String) {
        // Kokoro voice IDs encode the language via their first letter (a=US, b=UK, etc.)
        // so no separate language switch is needed — voice change is sufficient.
        currentLangCode = code
        log("Kokoro: lang code set to \(code)")
    }

    func shutdownKokoro() {
        // KokoroService manages its own lifecycle — nothing to tear down here.
    }

    // MARK: - Apple Voice Configuration

    func setAppleVoice(_ voiceId: String) {
        currentAppleVoiceId = voiceId
        log("Apple: voice set to \(voiceId.isEmpty ? "auto" : voiceId)")
    }

    func setAutoLanguageRouting(_ enabled: Bool) {
        autoLanguageRouting = enabled
        log("Routing: auto language routing \(enabled ? "enabled" : "disabled")")
    }

    /// Preview an Apple system voice from Settings. Runs on an isolated
    /// synthesizer and deliberately does NOT touch `isSpeaking`, so the menu
    /// bar icon and LCD widget stay idle while auditioning voices.
    func previewAppleVoice(text: String, voiceId: String) {
        guard !text.isEmpty else { return }
        log("Apple: preview(\(voiceId.isEmpty ? "auto" : voiceId)): \(text.prefix(80))")
        previewSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.resolveAppleVoice(preferredId: voiceId, languageHint: nil)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.05
        previewSynthesizer.speak(utterance)
    }

    // MARK: - TTS Dispatcher

    private func speak(_ text: String, provider: String = "apple") {
        guard !text.isEmpty else { return }
        // Auto language routing: Kokoro only speaks its 9 catalog languages.
        // When the text is in any other language (e.g. Russian), route it to
        // a matching Apple system voice instead of producing gibberish.
        let detectedLang = autoLanguageRouting ? Self.dominantLanguage(of: text) : nil
        switch provider {
        case "kokoro":
            if let lang = detectedLang, !KokoroVoiceCatalog.supportsLanguage(lang) {
                log("Routing: '\(lang)' not supported by Kokoro — using Apple system voice")
                speakWithApple(text, languageHint: lang)
                return
            }
            guard kokoroAvailable else {
                log("Kokoro unavailable — using Apple voice")
                speakWithApple(text, languageHint: detectedLang)
                return
            }
            speakWithKokoro(text)
        default:
            speakWithApple(text, languageHint: detectedLang)
        }
    }

    /// Detect the dominant language of the text as an ISO 639-1 style code
    /// (e.g. "ru", "en", "zh-Hans"). Returns nil when detection is inconclusive.
    static func dominantLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(400)))
        return recognizer.dominantLanguage?.rawValue
    }

    // MARK: - Kokoro Path

    private func speakWithKokoro(_ text: String) {
        log("Kokoro: speaking: \(text.prefix(200))")
        isSpeaking = true

        let voice = currentVoice
        Task { [weak self] in
            do {
                let data = try await KokoroService.shared.synthesize(text: text, voice: voice)
                await MainActor.run {
                    self?.playWavData(data)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.log("Kokoro: synthesis failed — \(error.localizedDescription) — falling back to Apple")
                    self.isSpeaking = false
                    self.speakWithApple(text)
                }
            }
        }
    }

    private func playWavData(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: "wav")
            playerDelegate = TTSPlaybackDelegate { [weak self] in
                DispatchQueue.main.async {
                    self?.isSpeaking = false
                    self?.audioPlayer = nil
                    self?.log("Kokoro: playback finished")
                }
            }
            player.delegate = playerDelegate
            audioPlayer = player
            isSpeaking = true
            player.play()
            log("Kokoro: playback started (\(data.count) bytes)")
        } catch {
            log("Kokoro: playback error — \(error.localizedDescription)")
            isSpeaking = false
        }
    }

    // MARK: - Apple TTS Path

    private func speakWithApple(_ text: String, languageHint: String? = nil) {
        guard !text.isEmpty else { return }
        log("speaking with Apple: \(text.prefix(200))")
        if isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.resolveAppleVoice(preferredId: currentAppleVoiceId, languageHint: languageHint)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.05

        speechDelegate = TTSSpeechDelegate { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.isSpeaking = false }
        }
        synthesizer.delegate = speechDelegate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Pick the Apple system voice to speak with.
    /// 1. The user-chosen voice — unless it clashes with the routed language.
    /// 2. The best-quality installed voice for the routed language.
    /// 3. The legacy default (premium Ava, then plain en-US).
    static func resolveAppleVoice(preferredId: String, languageHint: String?) -> AVSpeechSynthesisVoice? {
        let base = languageHint.map { String($0.prefix(2)) }
        if !preferredId.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: preferredId),
           base == nil || chosen.language.hasPrefix(base!) {
            return chosen
        }
        if let base {
            let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(base) }
            if let best = candidates.max(by: { qualityRank($0) < qualityRank($1) }) {
                return best
            }
        }
        if let premium = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Ava") {
            return premium
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
    }
}

// MARK: - Speech Delegates

final class TTSSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish() }
}

final class TTSPlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onFinish() }
}
