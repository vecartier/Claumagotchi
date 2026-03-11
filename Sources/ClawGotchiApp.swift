import SwiftUI
import AppKit

@main
struct ClawGotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = ClaudeMonitor()

    var body: some Scene {
        Window("ClawGotchi", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra {
            Text("Status: \(monitor.state.label)")
            if let pending = monitor.pendingPermission {
                Divider()
                Text("\(pending.tool): \(pending.summary)")
                    .font(.caption)
                Button("Allow") { monitor.respondToPermission(allow: true) }
                    .keyboardShortcut("a")
                Button("Deny") { monitor.respondToPermission(allow: false) }
                    .keyboardShortcut("d")
            }
            if monitor.state.canGoToConvo {
                Divider()
                Button("Go to Conversation") { monitor.goToConversation() }
                    .keyboardShortcut("g")
            }
            Divider()
            Button(monitor.autoAccept ? "Disable Auto-Accept" : "Enable Auto-Accept") {
                monitor.autoAccept.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Button(monitor.soundEnabled ? "Disable Sounds" : "Enable Sounds") {
                monitor.soundEnabled.toggle()
            }
            .keyboardShortcut("s")
            Button("Show / Hide") { Self.toggleMainWindow() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Quit Claumagotchi") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: EggIcon.image(attention: monitor.state.needsAttention))
        }
        .menuBarExtraStyle(.menu)
    }

    static func toggleMainWindow() {
        for window in NSApp.windows where window.title == "ClawGotchi" {
            window.isVisible ? window.orderOut(nil) : window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

// MARK: - Egg-shaped menu bar icon

enum EggIcon {
    static func image(attention: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        let img = NSImage(size: size, flipped: true) { _ in
            let color: NSColor = attention ? .systemOrange : .black

            // Draw a clean oval using NSBezierPath — smooth at any resolution
            let eggRect = NSRect(x: 2, y: 1, width: 14, height: 16)
            let egg = NSBezierPath(ovalIn: eggRect)
            color.setFill()
            egg.fill()

            // Cut out screen area
            let screen = NSRect(x: 5, y: 4, width: 8, height: 6)
            let screenPath = NSBezierPath(roundedRect: screen, xRadius: 1, yRadius: 1)
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            screenPath.fill()

            // Draw eyes + mouth inside screen cutout
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            color.setFill()
            NSRect(x: 7, y: 6, width: 1.5, height: 1.5).fill()
            NSRect(x: 10, y: 6, width: 1.5, height: 1.5).fill()
            NSRect(x: 8, y: 8, width: 3, height: 1).fill()

            // Three button dots below screen (cutout)
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            for dx: CGFloat in [5.5, 8.5, 11.5] {
                NSBezierPath(ovalIn: NSRect(x: dx, y: 12, width: 1.5, height: 1.5)).fill()
            }

            return true
        }

        img.isTemplate = !attention
        return img
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Window Configurator

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Remove all title bar buttons
            window.styleMask.remove(.titled)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // Constrain to screen bounds
            constrainToScreen(window)
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window, queue: .main
            ) { _ in constrainToScreen(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private func constrainToScreen(_ window: NSWindow) {
    guard let screen = window.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    var frame = window.frame

    if frame.minX < visible.minX { frame.origin.x = visible.minX }
    if frame.minY < visible.minY { frame.origin.y = visible.minY }
    if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
    if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }

    if frame != window.frame {
        window.setFrame(frame, display: false)
    }
}
