import SwiftUI

struct LyricsBarView: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var isHovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.isPlaying)) { timeline in
            let position = model.position(at: timeline.date)

            HStack(spacing: 24) {
                if model.showSongInfo {
                    SongIdentityView()
                        .frame(width: 210, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                LyricContentView(position: position)
                    .frame(maxWidth: .infinity)

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
                GeometryReader { proxy in
                    Capsule()
                        .fill(model.accentColor)
                        .frame(width: proxy.size.width * position / model.duration, height: 2)
                        .shadow(color: model.accentColor.opacity(0.8), radius: 5)
                }
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
                    text: model.localizedLyricText(model.title),
                    font: .system(size: 17, weight: .semibold, design: .rounded)
                )
                .frame(height: 22)
                Text(model.localizedLyricText(model.artist))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    @State private var textWidth = 0.0
    @State private var containerWidth = 0.0
    @State private var epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let overflow = max(0, textWidth - containerWidth)
            let travelTime = max(1.2, overflow / 28)
            let pause = 1.5
            let cycle = pause + travelTime + pause + travelTime
            let elapsed = timeline.date.timeIntervalSince(epoch).truncatingRemainder(dividingBy: cycle)
            let progress: Double = {
                if overflow == 0 || elapsed < pause { return 0 }
                if elapsed < pause + travelTime { return (elapsed - pause) / travelTime }
                if elapsed < pause + travelTime + pause { return 1 }
                return 1 - (elapsed - pause - travelTime - pause) / travelTime
            }()

            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: -overflow * progress)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MarqueeTextWidthKey.self, value: proxy.size.width)
                    }
                }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, value in containerWidth = value }
            }
        }
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
        .onChange(of: text) { _, _ in epoch = Date() }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
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
        VStack(spacing: 5) {
            if model.displayMode != .translation {
                KaraokeLine(words: model.currentLine.words, position: position)
                    .font(.system(size: 30 * model.fontScale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            if model.displayMode != .original, !model.translation.isEmpty {
                Text(model.translation)
                    .font(.system(size: 19 * model.fontScale, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if model.translation.isEmpty, let nextLine = model.nextLine {
                Text(model.localizedLyricText(nextLine.original))
                    .font(.system(size: 18 * model.fontScale, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.localizedLyricText(model.currentLine.original))，\(model.translation)")
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
