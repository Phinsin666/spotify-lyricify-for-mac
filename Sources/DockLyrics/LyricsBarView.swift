import AppKit
import SwiftUI

struct LyricsBarView: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 24) {
            if model.showSongInfo {
                SongIdentityView()
                    .frame(width: 250, alignment: .leading)
                    .clipped()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            LiveLyricContentView()
                .frame(maxWidth: .infinity)
                .clipped()

            HoverControls(isHovering: isHovering)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background {
            barBackground
            WindowDragSurface()
        }
        .overlay(alignment: .bottomLeading) {
            PlaybackProgressView()
                .frame(height: 2)
                .padding(.horizontal, 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .padding(2)
        .preferredColorScheme(model.preferredColorScheme)
    }

    @ViewBuilder
    private var barBackground: some View {
        if model.blurEnabled {
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(baseTint)
        } else {
            baseTint
        }
    }

    private var baseTint: some View {
        Color(nsColor: .windowBackgroundColor)
            .opacity(model.backgroundOpacity)
    }
}

private struct LiveLyricContentView: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.isPlaying)) { timeline in
            LyricContentView(position: model.lyricPosition(at: timeline.date))
        }
    }
}

private struct PlaybackProgressView: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.isPlaying)) { timeline in
            GeometryReader { proxy in
                let position = model.position(at: timeline.date)
                let progress = min(max(position / model.duration, 0), 1)
                Capsule()
                    .fill(model.accentColor)
                    .frame(width: proxy.size.width * progress, height: 2)
                    .shadow(color: model.accentColor.opacity(0.8), radius: 5)
            }
        }
    }
}

/// Restores the native background-drag behavior that a borderless SwiftUI
/// window otherwise loses. macOS also uses this path for three-finger drag.
private struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) { }

    private final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct SongIdentityView: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        HStack(spacing: 13) {
            ArtworkView(url: model.artworkURL)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                MarqueeText(
                    text: model.localizedLyricText(model.title)
                )
                .frame(width: 175, height: 22)
                Text(model.localizedLyricText(model.artist))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct MarqueeText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> MarqueeContainerView {
        MarqueeContainerView()
    }

    func updateNSView(_ nsView: MarqueeContainerView, context: Context) {
        nsView.setText(text)
    }

    final class MarqueeContainerView: NSView {
        private let textLayer = CATextLayer()
        private var currentText = ""
        private var animationSignature = ""
        private let textFont: NSFont = {
            let base = NSFont.systemFont(ofSize: 17, weight: .semibold)
            let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            return NSFont(descriptor: descriptor, size: 17) ?? base
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
            textLayer.alignmentMode = .left
            textLayer.isWrapped = false
            textLayer.truncationMode = .none
            layer?.addSublayer(textLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func setText(_ text: String) {
            guard text != currentText else { return }
            currentText = text
            updateLayerText()
            animationSignature = ""
            needsLayout = true
        }

        override func layout() {
            super.layout()
            guard bounds.width > 0, bounds.height > 0 else { return }

            let measured = measuredWidth
            let labelWidth = max(measured, bounds.width)
            let textHeight = ceil((currentText as NSString).size(withAttributes: attributes).height) + 2
            textLayer.contentsScale = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
            textLayer.frame = NSRect(
                x: 0,
                y: floor((bounds.height - textHeight) / 2),
                width: labelWidth,
                height: textHeight
            )

            let signature = "\(currentText)|\(Int(bounds.width.rounded()))|\(Int(measured.rounded()))"
            guard signature != animationSignature else { return }
            animationSignature = signature
            installAnimation(overflow: max(0, measured - bounds.width))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                animationSignature = ""
                needsLayout = true
            }
        }

        private func installAnimation(overflow: CGFloat) {
            textLayer.removeAnimation(forKey: "full-title-marquee")
            guard overflow > 1 else { return }

            let startPause = 1.5
            let endPause = 1.5
            let resetDuration = 0.01
            let travelTime = max(2.2, overflow / 22)
            let cycle = startPause + travelTime + endPause + resetDuration
            let startFraction = startPause / cycle
            let endTravelFraction = (startPause + travelTime) / cycle
            let endPauseFraction = (startPause + travelTime + endPause) / cycle

            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, 0, -overflow, -overflow, 0]
            animation.keyTimes = [
                0,
                NSNumber(value: startFraction),
                NSNumber(value: endTravelFraction),
                NSNumber(value: endPauseFraction),
                1
            ]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .linear)
            ]
            animation.duration = cycle
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            textLayer.add(animation, forKey: "full-title-marquee")
        }

        private var measuredWidth: CGFloat {
            ceil((currentText as NSString).size(withAttributes: attributes).width) + 4
        }

        private func updateLayerText() {
            textLayer.string = NSAttributedString(
                string: currentText,
                attributes: attributes
            )
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateLayerText()
        }

        private var attributes: [NSAttributedString.Key: Any] {
            [.font: textFont, .foregroundColor: NSColor.labelColor]
        }
    }
}

private struct ArtworkView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                placeholder.overlay { ProgressView().controlSize(.small) }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [.indigo, .purple.opacity(0.8), .orange.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct LyricContentView: View {
    @EnvironmentObject private var model: PlaybackModel
    let position: TimeInterval

    var body: some View {
        let displayed = model.displayedLines(at: position)
        let translation = model.localizedTranslation(for: displayed.current)

        VStack(spacing: 5) {
            if model.displayMode != .translation {
                KaraokeLine(words: displayed.current.words, position: position)
                    .font(.system(size: 30 * model.fontScale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            if model.displayMode != .original, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: 19 * model.fontScale, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if translation.isEmpty, let nextLine = displayed.next {
                Text(model.localizedLyricText(nextLine.original))
                    .font(.system(size: 18 * model.fontScale, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.localizedLyricText(displayed.current.original))，\(translation)")
    }
}

private struct KaraokeLine: View {
    @EnvironmentObject private var model: PlaybackModel
    let words: [TimedWord]
    let position: TimeInterval

    var body: some View {
        HStack(spacing: 7) {
            ForEach(words) { word in
                Text(model.localizedLyricText(word.text))
                    .foregroundStyle(color(for: word))
                    .shadow(color: glow(for: word), radius: 7)
                    .animation(.linear(duration: 0.12), value: position)
            }
        }
    }

    private func color(for word: TimedWord) -> Color {
        if position >= word.end { return model.accentColor }
        if position >= word.start { return model.accentColor.opacity(0.92) }
        return .primary
    }

    private func glow(for word: TimedWord) -> Color {
        position >= word.start && position < word.end
            ? model.accentColor.opacity(0.55)
            : .clear
    }
}

private struct HoverControls: View {
    @EnvironmentObject private var model: PlaybackModel
    let isHovering: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isHovering {
                Button { model.restart() } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { model.nextTrack() } label: {
                    Image(systemName: "forward.end.fill")
                }
            }

            SettingsLink {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.secondary)
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}
