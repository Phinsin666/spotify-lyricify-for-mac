import AppKit
import SwiftUI

@main
struct DockLyricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PlaybackModel()

    var body: some Scene {
        WindowGroup {
            LyricsBarView()
                .environmentObject(model)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A regular activation policy gives the app its expected Dock presence.
        // The lyrics window itself remains borderless and floating.
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        } else if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                  let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        installStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeStatusIcon()
            button.toolTip = "Spotify Lyricify for Mac"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "顯示歌詞視窗", action: #selector(showLyricsWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "播放／暫停", action: #selector(toggleSpotifyPlayback), keyEquivalent: "")
        menu.addItem(withTitle: "上一首", action: #selector(previousSpotifyTrack), keyEquivalent: "")
        menu.addItem(withTitle: "下一首", action: #selector(nextSpotifyTrack), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束 Spotify Lyricify for Mac", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            func stroke(_ points: [NSPoint], width: CGFloat = 2.15) {
                guard let first = points.first else { return }
                let path = NSBezierPath()
                path.lineWidth = width
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: first)
                points.dropFirst().forEach { path.line(to: $0) }
                path.stroke()
            }

            // The same three flowing lyric strokes used by the Dock icon,
            // simplified for the menu bar's very small monochrome canvas.
            stroke([NSPoint(x: 5.2, y: 14.2), NSPoint(x: 3.9, y: 8.0), NSPoint(x: 13.9, y: 10.1)])
            stroke([NSPoint(x: 8.7, y: 12.2), NSPoint(x: 13.1, y: 13.1)])
            stroke([NSPoint(x: 3.8, y: 4.5), NSPoint(x: 13.8, y: 6.4)])
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "歌詞"
        return image
    }

    @objc private func showLyricsWindow() {
        NSApp.windows.first(where: { $0.level == .floating })?.orderFrontRegardless()
    }

    @objc private func toggleSpotifyPlayback() {
        runSpotifyCommand("playpause")
    }

    @objc private func previousSpotifyTrack() {
        runSpotifyCommand("previous track")
    }

    @objc private func nextSpotifyTrack() {
        runSpotifyCommand("next track")
    }

    @objc private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func runSpotifyCommand(_ command: String) {
        let source = "tell application \"Spotify\" to \(command)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}


private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Position only once. Reapplying the initial frame on every SwiftUI state
        // update would snap the window back while the user is dragging it.
    }

    @MainActor
    private func configure(_ window: NSWindow?) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }

        // A SwiftUI hidden title bar still reserves a full glass title-bar region.
        // Make the host window genuinely borderless so only LyricsBarView draws.
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let frame = screen.frame
        let visible = screen.visibleFrame
        let bottomInset = max(0, visible.minY - frame.minY)
        let dockLikeHeight = bottomInset > 40 ? min(max(bottomInset - 6, 96), 132) : 112
        let width = min(1600, visible.width - 72)
        let size = NSSize(width: width, height: dockLikeHeight)
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size

        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.minY + 10
        )
        if abs(window.frame.origin.x - origin.x) > 2 || abs(window.frame.origin.y - origin.y) > 2 {
            window.setFrameOrigin(origin)
        }
    }
}
