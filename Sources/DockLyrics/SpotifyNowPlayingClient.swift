import AppKit
import Foundation

struct SpotifySnapshot: Sendable, Equatable {
    enum PlaybackState: String, Sendable {
        case playing
        case paused
        case stopped
    }

    let title: String
    let artist: String
    let album: String
    let trackID: String
    let artworkURL: URL?
    let duration: TimeInterval
    let position: TimeInterval
    let state: PlaybackState
}

enum SpotifyConnectionState: String, Error, Sendable {
    case connected = "Spotify 已連線"
    case notRunning = "Spotify 未執行"
    case permissionRequired = "需要 Spotify 自動化權限"
}

/// Reads Spotify for Mac's AppleScript playback dictionary. This does not need a
/// Spotify Web API client ID and only observes the user's local Spotify app.
@MainActor
final class SpotifyNowPlayingClient {
    func snapshot() -> Result<SpotifySnapshot?, SpotifyConnectionState> {
        let scriptSource = #"""
        tell application "System Events"
            set spotifyRunning to (name of processes) contains "Spotify"
        end tell
        if spotifyRunning is false then return "__NOT_RUNNING__"

        tell application "Spotify"
            if player state is stopped then return "__STOPPED__"
            set unitSeparator to ASCII character 31
            set currentItem to current track
            set coverURL to ""
            try
                set coverValue to artwork url of currentItem
                if coverValue is not missing value then set coverURL to coverValue as text
            end try
            set payload to (name of currentItem) & unitSeparator & (artist of currentItem) & unitSeparator & (album of currentItem) & unitSeparator & (spotify url of currentItem) & unitSeparator & coverURL & unitSeparator & ((duration of currentItem) as text) & unitSeparator & ((player position) as text) & unitSeparator & ((player state) as text)
            return payload
        end tell
        """#

        var error: NSDictionary?
        guard let result = NSAppleScript(source: scriptSource)?.executeAndReturnError(&error) else {
            return .failure(.permissionRequired)
        }

        if error != nil { return .failure(.permissionRequired) }
        let value = result.stringValue ?? ""
        if value == "__NOT_RUNNING__" { return .failure(.notRunning) }
        if value == "__STOPPED__" { return .success(nil) }

        let fields = value.components(separatedBy: String(UnicodeScalar(31)))
        guard fields.count == 8 else { return .success(nil) }

        let state = SpotifySnapshot.PlaybackState(rawValue: fields[7]) ?? .paused
        var title = fields[0]
        var artist = fields[1]
        if artist.isEmpty, let separator = title.range(of: " - ") {
            artist = String(title[..<separator.lowerBound])
            title = String(title[separator.upperBound...])
        }
        return .success(
            SpotifySnapshot(
                title: title,
                artist: artist,
                album: fields[2],
                trackID: fields[3],
                artworkURL: URL(string: fields[4]),
                duration: (Double(fields[5]) ?? 0) / 1_000,
                position: Double(fields[6]) ?? 0,
                state: state
            )
        )
    }

    func togglePlayback() {
        run(command: "playpause")
    }

    func previousTrack() {
        run(command: "previous track")
    }

    func nextTrack() {
        run(command: "next track")
    }

    private func run(command: String) {
        let source = "tell application \"Spotify\" to \(command)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
