import SwiftUI

struct ScreenView: View {
    @EnvironmentObject var monitor: ClaudeMonitor
    @State private var animFrame = 0

    private let lcdBg = Color(hex: "A8AA6A")
    private let lcdOn = Color(hex: "3A3A2E")
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Rectangle().fill(lcdBg)

            VStack(spacing: 0) {
                // Top icon row — status indicators
                HStack(spacing: 0) {
                    LCDIcon(symbol: "exclamationmark.triangle.fill",
                            active: monitor.state == .needsYou)
                    Spacer()
                    LCDIcon(symbol: "bolt.fill",
                            active: monitor.state == .thinking)
                    Spacer()
                    LCDIcon(symbol: "checkmark.circle.fill",
                            active: monitor.state == .finished)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

                // Character
                PixelCharacterView(state: monitor.state, frame: animFrame)
                    .frame(maxHeight: .infinity)

                // Status label
                Text(monitor.state.label)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(lcdOn)
                    .opacity(monitor.state.needsAttention
                             ? (animFrame % 2 == 0 ? 1 : 0.15) : 1)

                // Detail line
                Text(detailText)
                    .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                    .foregroundColor(lcdOn.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 10, alignment: .top)
                    .padding(.bottom, 3)
            }
            .padding(.horizontal, 4)
        }
        .onReceive(timer) { _ in animFrame += 1 }
    }

    private var detailText: String {
        if let p = monitor.pendingPermission {
            return "\(p.tool): \(p.summary)"
        }
        return ""
    }
}

// MARK: - LCD Status Icon

struct LCDIcon: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(Color(hex: "3A3A2E").opacity(active ? 0.85 : 0.08))
    }
}

// MARK: - Pixel Character

struct PixelCharacterView: View {
    let state: ClaudeState
    let frame: Int

    private let pixelSize: CGFloat = 2.5
    private let onColor = Color(hex: "3A3A2E")

    private var currentSprite: [String] {
        let sprites = spritesForState(state)
        return sprites[frame % sprites.count]
    }

    var body: some View {
        Canvas { context, size in
            let sprite = currentSprite
            guard let firstRow = sprite.first else { return }
            let cols = firstRow.count, rows = sprite.count
            let totalW = CGFloat(cols) * pixelSize
            let totalH = CGFloat(rows) * pixelSize
            let ox = (size.width - totalW) / 2
            let oy = (size.height - totalH) / 2

            for (row, line) in sprite.enumerated() {
                for (col, char) in line.enumerated() {
                    if char == "#" {
                        let rect = CGRect(
                            x: ox + CGFloat(col) * pixelSize,
                            y: oy + CGFloat(row) * pixelSize,
                            width: pixelSize, height: pixelSize
                        )
                        context.fill(Path(rect), with: .color(onColor))
                    }
                }
            }
        }
    }

    private func spritesForState(_ state: ClaudeState) -> [[String]] {
        switch state {
        case .thinking: [Sprites.thinking1, Sprites.thinking2, Sprites.working1, Sprites.working2]
        case .needsYou: [Sprites.alert1, Sprites.alert2]
        case .finished: [Sprites.happy1, Sprites.happy2]
        }
    }
}

// MARK: - Sprites (14 wide x 12 tall)

enum Sprites {
    static let thinking1: [String] = [
        "......##......",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#...##..##.#.",
        ".#..........#.",
        ".#....##....#.",
        ".#..........#.",
        "..##########..",
        "....######....",
        "..............",
        "..##..##..##..",
    ]
    static let thinking2: [String] = [
        "......##......",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#.##..##...#.",
        ".#..........#.",
        ".#....##....#.",
        ".#..........#.",
        "..##########..",
        "....######....",
        "..............",
        "....##..##....",
    ]
    static let working1: [String] = [
        "......##......",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#..##..##..#.",
        ".#..........#.",
        ".#...####...#.",
        ".#..........#.",
        "############..",
        "....######....",
        "...#......#...",
        "..##......##..",
    ]
    static let working2: [String] = [
        "......##......",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#..##..##..#.",
        ".#..........#.",
        ".#...####...#.",
        ".#..........#.",
        "..############",
        "....######....",
        "...#......#...",
        "..##......##..",
    ]
    static let alert1: [String] = [
        "......##......",
        "......##......",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#..##..##..#.",
        ".#..........#.",
        ".#...####...#.",
        "..##########..",
        "....######....",
        "..............",
        "..##......##..",
    ]
    static let alert2: [String] = [
        "..............",
        "......##......",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#..##..##..#.",
        ".#..........#.",
        ".#...####...#.",
        ".#..........#.",
        "..##########..",
        "...#......#...",
        "..##......##..",
    ]
    static let happy1: [String] = [
        ".#...##....#..",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#..##..##..#.",
        ".#..........#.",
        ".#.########.#.",
        ".#..........#.",
        "..##########..",
        "....######....",
        "...#......#...",
        "..##......##..",
    ]
    static let happy2: [String] = [
        "..#..##...#...",
        "....######....",
        "..##########..",
        ".#..........#.",
        ".#..##..##..#.",
        ".#..........#.",
        ".#.########.#.",
        ".#..........#.",
        "..##########..",
        "....######....",
        "...#......#...",
        "..##......##..",
    ]
}
