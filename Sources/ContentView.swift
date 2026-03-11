import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: ClaudeMonitor

    private let shellW: CGFloat = 186
    private let shellH: CGFloat = 224

    var body: some View {
        ZStack {
            // Diffused drop shadow
            Ellipse()
                .fill(.black.opacity(0.3))
                .frame(width: shellW + 10, height: shellH + 10)
                .blur(radius: 20)
                .offset(y: 6)

            // Main shell body
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "F09050"),
                            Color(hex: "E07838"),
                            Color(hex: "D06828"),
                            Color(hex: "C05820"),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: shellW, height: shellH)

            // Noise texture overlay for plastic grain
            NoiseView()
                .frame(width: shellW, height: shellH)
                .clipShape(Ellipse())
                .opacity(0.08)
                .allowsHitTesting(false)

            // Top-left glossy highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.08),
                            .clear,
                        ],
                        center: UnitPoint(x: 0.3, y: 0.12),
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: shellW, height: shellH)

            // Rim bevel
            Ellipse()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.1),
                            .clear,
                            .black.opacity(0.12),
                            .black.opacity(0.2),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: shellW, height: shellH)

            // Content layout
            VStack(spacing: 4) {
                // Pixel title
                PixelTitle()
                    .frame(width: 160, height: 14)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                // Screen
                ZStack {
                    // LCD screen
                    ScreenView()
                        .environmentObject(monitor)
                        .frame(width: 116, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    // Inner shadow — crisp stroke
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.6),
                                    .black.opacity(0.15),
                                    .black.opacity(0.03),
                                    .black.opacity(0.08),
                                    .black.opacity(0.3),
                                ],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 116, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .allowsHitTesting(false)

                    // Side inner shadow
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.2),
                                    .clear,
                                    .clear,
                                    .black.opacity(0.12),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 116, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .allowsHitTesting(false)
                }

                Spacer().frame(height: 6)

                // Buttons — nearly flat row, deny+allow slightly elevated
                ZStack {
                    // Deny (left, slightly up)
                    ActionButton(
                        symbol: "xmark", size: 7,
                        colors: [Color(hex: "A060D0"), Color(hex: "7840A8")],
                        active: monitor.state.needsAttention
                    ) { monitor.respondToPermission(allow: false) }
                    .accessibilityLabel("Deny permission")
                    .offset(x: -32, y: -7)

                    // Go to conversation (center)
                    ActionButton(
                        symbol: "arrow.up.forward", size: 8,
                        colors: [Color(hex: "A060D0"), Color(hex: "7840A8")],
                        active: monitor.state.canGoToConvo || monitor.state.needsAttention,
                        pulse: monitor.state.canGoToConvo
                    ) { monitor.goToConversation() }
                    .accessibilityLabel("Go to conversation")

                    // Allow (right, slightly up)
                    ActionButton(
                        symbol: "checkmark", size: 8,
                        colors: [Color(hex: "A060D0"), Color(hex: "7840A8")],
                        active: monitor.state.needsAttention,
                        pulse: monitor.state.needsAttention
                    ) { monitor.respondToPermission(allow: true) }
                    .accessibilityLabel("Allow permission")
                    .offset(x: 32, y: -7)
                }
                .animation(.easeInOut(duration: 0.3), value: monitor.state)
                .frame(height: 34)
            }
        }
        .frame(width: 250, height: 300)
        .background(Color.clear)
        .contextMenu {
            Button("Quit Claumagotchi") { NSApplication.shared.terminate(nil) }
        }
    }
}

// MARK: - Noise Texture

struct NoiseView: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: 42)
            let step: CGFloat = 1.5
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let val = rng.next()
                    if val < 0.45 {
                        let rect = CGRect(x: x, y: y, width: step, height: step)
                        context.fill(Path(rect), with: .color(.white.opacity(val * 0.7)))
                    } else if val > 0.55 {
                        let rect = CGRect(x: x, y: y, width: step, height: step)
                        context.fill(Path(rect), with: .color(.black.opacity((1.0 - val) * 0.5)))
                    }
                    x += step
                }
                y += step
            }
        }
    }
}

struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state &>> 1) / Double(UInt64.max >> 1)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let symbol: String
    var size: CGFloat = 9
    let colors: [Color]
    let active: Bool
    var pulse: Bool = false
    let action: () -> Void

    @State private var animating = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Recessed well the button sits in
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 27, height: 27)
                    .blur(radius: 1)

                // Button face — convex gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: active ? [
                                colors[0].opacity(0.9),
                                colors[1],
                            ] : [
                                Color(hex: "D8D4CE"),
                                Color(hex: "BAB6B0"),
                            ],
                            center: UnitPoint(x: 0.4, y: 0.35),
                            startRadius: 0,
                            endRadius: 14
                        )
                    )
                    .frame(width: 24, height: 24)

                // Top specular highlight
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(active ? 0.4 : 0.2),
                                .white.opacity(0.05),
                                .clear,
                            ],
                            startPoint: .top, endPoint: .center
                        )
                    )
                    .frame(width: 24, height: 24)

                // Bottom catch light
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.06),
                            ],
                            startPoint: .center, endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 24)

                // Rim
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.25),
                                .clear,
                                .black.opacity(0.2),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                    .frame(width: 24, height: 24)

                Image(systemName: symbol)
                    .font(.system(size: size, weight: .black))
                    .foregroundColor(active ? .white : Color(hex: "A8A4A0"))
                    .shadow(color: .black.opacity(active ? 0.3 : 0), radius: 0.5, y: 0.5)
            }
            .frame(width: 28, height: 28)
            .scaleEffect(pulse && animating ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .onChange(of: pulse) {
            if pulse {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    animating = true
                }
            } else {
                withAnimation(.none) { animating = false }
            }
        }
    }
}

// MARK: - Pixel Title

struct PixelTitle: View {
    private let px: CGFloat = 1.4
    private let gap: CGFloat = 1.0
    private let color = Color(hex: "A060D0")
    private let highlight = Color(hex: "C890F0")
    private let shadow = Color(hex: "3A1060")

    // Rounded, playful letterforms — inspired by Tamagotchi logo
    private static let font: [Character: [String]] = [
        "C": [".###.", "#...#", "#....", "#....", "#...#", ".###."],
        "L": ["#....", "#....", "#....", "#....", "#....", "#####"],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#"],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#"],
        "G": [".###.", "#....", "#.###", "#...#", "#...#", ".###."],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", ".###."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "H": ["#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".#.", ".#.", ".#.", ".#.", ".#.", ".#."],
    ]

    var body: some View {
        Canvas { context, size in
            let text: [Character] = Array("CLAUMAGOTCHI")

            var totalW: CGFloat = 0
            for ch in text {
                if let g = Self.font[ch] {
                    totalW += CGFloat(g[0].count) * px + gap
                }
            }
            totalW -= gap

            var x = (size.width - totalW) / 2
            let y = (size.height - 6 * px) / 2

            // Shadow pass (down-right)
            for ch in text {
                guard let glyph = Self.font[ch] else { continue }
                let w = CGFloat(glyph[0].count)
                for (row, line) in glyph.enumerated() {
                    for (col, p) in line.enumerated() where p == "#" {
                        let rect = CGRect(
                            x: x + CGFloat(col) * px + 1,
                            y: y + CGFloat(row) * px + 1,
                            width: px, height: px
                        )
                        context.fill(Path(rect), with: .color(shadow))
                    }
                }
                x += w * px + gap
            }

            // Highlight pass (up-left)
            x = (size.width - totalW) / 2
            for ch in text {
                guard let glyph = Self.font[ch] else { continue }
                let w = CGFloat(glyph[0].count)
                for (row, line) in glyph.enumerated() {
                    for (col, p) in line.enumerated() where p == "#" {
                        let rect = CGRect(
                            x: x + CGFloat(col) * px - 0.4,
                            y: y + CGFloat(row) * px - 0.4,
                            width: px, height: px
                        )
                        context.fill(Path(rect), with: .color(highlight.opacity(0.4)))
                    }
                }
                x += w * px + gap
            }

            // Main pass
            x = (size.width - totalW) / 2
            for ch in text {
                guard let glyph = Self.font[ch] else { continue }
                let w = CGFloat(glyph[0].count)
                for (row, line) in glyph.enumerated() {
                    for (col, p) in line.enumerated() where p == "#" {
                        let rect = CGRect(
                            x: x + CGFloat(col) * px,
                            y: y + CGFloat(row) * px,
                            width: px, height: px
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
                x += w * px + gap
            }
        }
    }
}

// MARK: - Color Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
