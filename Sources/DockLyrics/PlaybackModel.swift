import SwiftUI

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case traditional = "繁體中文"
    case simplified = "简体中文"

    var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case automatic = "自動"
    case dark = "深色"
    case light = "淺色"

    var id: String { rawValue }
}

enum LyricDisplayMode: String, CaseIterable, Identifiable {
    case bilingual = "雙語"
    case original = "僅原文"
    case translation = "僅譯文"

    var id: String { rawValue }
}

struct TimedWord: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct LyricLine: Sendable {
    let original: String
    let traditionalTranslation: String
    let simplifiedTranslation: String
    let words: [TimedWord]
    let start: TimeInterval
    let end: TimeInterval
}

@MainActor
final class PlaybackModel: ObservableObject {
    @Published var isPlaying = true
    @Published var interfaceLanguage: InterfaceLanguage = .traditional
    @Published var appearance: AppearanceMode = .automatic
    @Published var displayMode: LyricDisplayMode = .bilingual
    @Published var fontScale = 1.0
    @Published var backgroundOpacity = 0.72
    @Published var blurEnabled = true
    @Published var showSongInfo = true
    @Published var useArtworkAccent = true
    @Published var accentColor = Color(red: 0.12, green: 0.90, blue: 0.47)
    @Published var lyricOffset = UserDefaults.standard.object(forKey: "lyricOffset") as? Double ?? 0.12 {
        didSet { UserDefaults.standard.set(lyricOffset, forKey: "lyricOffset") }
    }

    @Published var title = "Night Drive"
    @Published var artist = "Maya Lane"
    @Published var album = "Midnight Roads"
    @Published var artworkURL: URL?
    @Published var spotifyState: SpotifyConnectionState = .notRunning
    @Published var isUsingSpotify = false
    @Published private(set) var currentLine: LyricLine
    @Published private(set) var nextLine: LyricLine?

    private(set) var duration: TimeInterval = 18
    private(set) var startedAt = Date()
    private var pausedPosition: TimeInterval = 0
    private var currentTrackID: String?
    private let spotify = SpotifyNowPlayingClient()
    private let artworkResolver = ArtworkResolver()
    private let lyricRouter = LyricsProviderRouter(
        providers: [QQLyricsProvider(), LRCLIBProvider(), NetEaseLyricsProvider()]
    )
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lyricLines: [LyricLine] = []

    private static let demoLine = LyricLine(
        original: "We keep driving through the night",
        traditionalTranslation: "我們沿著夜色繼續前行",
        simplifiedTranslation: "我们沿着夜色继续前行",
        words: [
            TimedWord(text: "We", start: 0.0, end: 1.4),
            TimedWord(text: "keep", start: 1.4, end: 3.2),
            TimedWord(text: "driving", start: 3.2, end: 6.2),
            TimedWord(text: "through", start: 6.2, end: 8.4),
            TimedWord(text: "the", start: 8.4, end: 10.0),
            TimedWord(text: "night", start: 10.0, end: 13.0)
        ],
        start: 0,
        end: 13
    )

    init() {
        currentLine = Self.demoLine
        nextLine = nil
        Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshSpotify()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return pausedPosition }
        return (pausedPosition + date.timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: duration)
    }

    /// Mirrors the car version's continuously interpolated playback clock and
    /// its small 120 ms lyric lead. The user can fine-tune provider-specific
    /// timestamp drift without changing the actual playback progress display.
    func lyricPosition(at date: Date) -> TimeInterval {
        min(max(position(at: date) + lyricOffset, 0), duration)
    }

    func displayedLines(at position: TimeInterval) -> (current: LyricLine, next: LyricLine?) {
        guard !lyricLines.isEmpty else { return (currentLine, nextLine) }
        let index = lyricLines.lastIndex(where: { $0.start <= position }) ?? 0
        return (
            lyricLines[index],
            index + 1 < lyricLines.count ? lyricLines[index + 1] : nil
        )
    }

    func togglePlayback(at date: Date = Date()) {
        if isUsingSpotify {
            spotify.togglePlayback()
            isPlaying.toggle()
            startedAt = date
            return
        }

        if isPlaying {
            pausedPosition = position(at: date)
        } else {
            startedAt = date
        }
        isPlaying.toggle()
    }

    func restart() {
        if isUsingSpotify {
            spotify.previousTrack()
            return
        }
        pausedPosition = 0
        startedAt = Date()
    }

    func nextTrack() {
        guard isUsingSpotify else {
            restart()
            return
        }
        spotify.nextTrack()
    }

    var translation: String {
        localizedTranslation(for: currentLine)
    }

    func localizedTranslation(for line: LyricLine) -> String {
        interfaceLanguage == .traditional
            ? line.traditionalTranslation
            : line.simplifiedTranslation
    }

    func localizedLyricText(_ text: String) -> String {
        let transform = interfaceLanguage == .traditional ? "Hans-Hant" : "Hant-Hans"
        return text.applyingTransform(StringTransform(transform), reverse: false) ?? text
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .automatic: nil
        case .dark: .dark
        case .light: .light
        }
    }

    private func refreshSpotify() {
        switch spotify.snapshot() {
        case .failure(let state):
            spotifyState = state
            isUsingSpotify = false
        case .success(nil):
            spotifyState = .connected
            isUsingSpotify = true
            isPlaying = false
        case .success(let snapshot?):
            spotifyState = .connected
            isUsingSpotify = true
            title = snapshot.title
            artist = snapshot.artist
            album = snapshot.album
            duration = max(snapshot.duration, 1)
            pausedPosition = snapshot.position
            startedAt = Date()
            isPlaying = snapshot.state == .playing

            if currentTrackID != snapshot.trackID {
                currentTrackID = snapshot.trackID
                currentLine = placeholderLine(for: snapshot)
                nextLine = nil
                loadLyrics(for: snapshot)
                loadArtwork(for: snapshot)
            } else {
                updateDisplayedLines(at: snapshot.position)
            }
        }
    }

    private func loadArtwork(for snapshot: SpotifySnapshot) {
        artworkTask?.cancel()
        artworkURL = snapshot.artworkURL
        let trackID = snapshot.trackID
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await artworkResolver.artworkURL(for: snapshot)
            guard !Task.isCancelled, currentTrackID == trackID else { return }
            artworkURL = resolved
        }
    }

    private func loadLyrics(for snapshot: SpotifySnapshot) {
        lyricsTask?.cancel()
        lyricLines = []
        let trackID = snapshot.trackID
        let identity = TrackIdentity(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration
        )

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let result = await lyricRouter.bestLyrics(for: identity)
            guard !Task.isCancelled, currentTrackID == trackID else { return }

            if let lines = result?.lines, !lines.isEmpty {
                lyricLines = lines
                updateDisplayedLines(at: pausedPosition)
            } else {
                currentLine = noLyricsLine(for: snapshot)
                nextLine = nil
            }
        }
    }

    private func updateDisplayedLines(at position: TimeInterval) {
        guard !lyricLines.isEmpty else { return }
        let index = lyricLines.lastIndex(where: { $0.start <= position }) ?? 0
        let line = lyricLines[index]
        if line.start != currentLine.start { currentLine = line }
        nextLine = index + 1 < lyricLines.count ? lyricLines[index + 1] : nil
    }

    private func placeholderLine(for snapshot: SpotifySnapshot) -> LyricLine {
        let traditional = "正在為〈\(snapshot.title)〉配對同步歌詞…"
        let simplified = "正在为《\(snapshot.title)》匹配同步歌词…"
        return LyricLine(
            original: snapshot.title,
            traditionalTranslation: traditional,
            simplifiedTranslation: simplified,
            words: [TimedWord(text: snapshot.title, start: 0, end: snapshot.duration)],
            start: 0,
            end: snapshot.duration
        )
    }

    private func noLyricsLine(for snapshot: SpotifySnapshot) -> LyricLine {
        let traditional = "這首歌曲暫時沒有可用的同步歌詞"
        let simplified = "这首歌曲暂时没有可用的同步歌词"
        return LyricLine(
            original: snapshot.title,
            traditionalTranslation: traditional,
            simplifiedTranslation: simplified,
            words: [TimedWord(text: snapshot.title, start: 0, end: snapshot.duration)],
            start: 0,
            end: snapshot.duration
        )
    }
}
