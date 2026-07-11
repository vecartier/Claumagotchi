import SwiftUI
import AVFoundation

struct SettingsVoiceOverSection: View {
    @EnvironmentObject var monitor: ClaudeMonitor

    private var currentVoices: [KokoroVoiceCatalog.Voice] {
        KokoroVoiceCatalog.voicesByLang[monitor.kokoroLangCode] ?? KokoroVoiceCatalog.voicesByLang["a"]!
    }

    private var sortedLangCodes: [(code: String, name: String)] {
        KokoroVoiceCatalog.languageNames
            .map { (code: $0.key, name: $0.value) }
            .sorted { a, b in
                if a.code == "a" { return true }
                if b.code == "a" { return false }
                return a.name < b.name
            }
    }

    /// All installed Apple system voices, sorted by language then name so the
    /// menu groups languages together.
    private var appleVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { a, b in
                if a.language != b.language { return a.language < b.language }
                return a.name < b.name
            }
    }

    private func applePreviewText(for voiceId: String) -> String {
        let lang = AVSpeechSynthesisVoice(identifier: voiceId)?.language ?? "en-US"
        return lang.hasPrefix("ru") ? "Привет! Вот так я звучу." : "Hi, this is how I sound."
    }

    var body: some View {
        Section {
            Toggle(isOn: $monitor.voiceOver) {
                Label("Read Over", systemImage: "speaker.wave.2.fill")
            }
            .toggleStyle(.switch)

            Text("When enabled, Claude's responses are read aloud automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Speech Synthesis") {
            Picker("Provider", selection: $monitor.ttsProvider) {
                Text("Kokoro (local)").tag("kokoro")
                Text("Apple").tag("apple")
            }
            .pickerStyle(.menu)

            if monitor.ttsProvider == "kokoro" {
                Picker("Language", selection: $monitor.kokoroLangCode) {
                    ForEach(sortedLangCodes, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Picker("Voice", selection: $monitor.kokoroVoice) {
                        ForEach(currentVoices, id: \.id) { voice in
                            Text("\(voice.gender) — \(voice.label)").tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        let label = currentVoices.first(where: { $0.id == monitor.kokoroVoice })?.label ?? "this voice"
                        monitor.ttsService.previewKokoroVoice(
                            text: "Hi, I'm \(label). This is how I sound.",
                            voice: monitor.kokoroVoice
                        )
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Preview voice")
                }
            }

            if monitor.ttsProvider == "apple" || monitor.autoLanguageRouting {
                HStack {
                    Picker("Apple Voice", selection: $monitor.appleVoiceId) {
                        Text("Automatic").tag("")
                        ForEach(appleVoices, id: \.identifier) { voice in
                            Text("\(voice.name) — \(voice.language)").tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        monitor.ttsService.previewAppleVoice(
                            text: applePreviewText(for: monitor.appleVoiceId),
                            voiceId: monitor.appleVoiceId
                        )
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Preview voice")
                }
            }

            Toggle(isOn: $monitor.autoLanguageRouting) {
                Label("Auto Language Routing", systemImage: "globe")
            }
            .toggleStyle(.switch)

            Text("Languages Kokoro can't speak (e.g. Russian) are read with a matching Apple system voice. Install more voices in System Settings → Accessibility → Spoken Content.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

    }
}
