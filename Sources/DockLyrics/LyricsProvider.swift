import Foundation

struct TrackIdentity: Sendable {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval?
}

struct LyricsResult: Sendable {
    let lines: [LyricLine]
    let confidence: Double

    var translationLineCount: Int {
        lines.reduce(into: 0) { count, line in
            if !line.simplifiedTranslation.isEmpty {
                count += 1
            }
        }
    }
}

protocol LyricsProvider: Sendable {
    var id: String { get }
    func lyrics(for track: TrackIdentity) async throws -> LyricsResult?
}

/// Keeps UI code independent from any one lyric service. Network-backed providers
/// can be added later without changing the player or lyric rendering views.
actor LyricsProviderRouter {
    private let providers: [any LyricsProvider]

    init(providers: [any LyricsProvider]) {
        self.providers = providers
    }

    func bestLyrics(for track: TrackIdentity) async -> LyricsResult? {
        var candidates: [LyricsResult] = []
        for provider in providers {
            guard let candidate = try? await provider.lyrics(for: track) else { continue }
            candidates.append(candidate)
        }

        // Match the behaviour of the earlier car-lyrics app: a usable Chinese
        // translation is more valuable than a tiny source-confidence advantage.
        // QQ and NetEase often disagree about which release carries `trans` /
        // `tlyric`, so never stop at the first original-only result.
        return candidates.max { lhs, rhs in
            if lhs.translationLineCount != rhs.translationLineCount {
                return lhs.translationLineCount < rhs.translationLineCount
            }
            return lhs.confidence < rhs.confidence
        }
    }
}

struct QQLyricsProvider: LyricsProvider {
    let id = "qqmusic"

    func lyrics(for track: TrackIdentity) async throws -> LyricsResult? {
        guard var search = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp") else {
            return nil
        }
        search.queryItems = [
            URLQueryItem(name: "w", value: "\(track.title) \(track.artist)"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "n", value: "10"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let searchURL = search.url else { return nil }
        let searchData = try await fetch(searchURL)
        let envelope = try JSONDecoder().decode(QQSearchEnvelope.self, from: searchData)
        guard let candidates = envelope.data.song.list, !candidates.isEmpty else { return nil }

        let ordered = candidates.sorted { score($0, track: track) < score($1, track: track) }
        for candidate in ordered.prefix(5) where score(candidate, track: track) < 45 {
            guard let response = try? await fetchLyrics(songMID: candidate.songmid),
                  let original = response.lyric,
                  !original.isEmpty else { continue }
            let lines = LRCParser.lines(
                original: original,
                translation: response.trans,
                duration: track.duration
            )
            if !lines.isEmpty {
                let hasTranslation = response.trans?.isEmpty == false
                return LyricsResult(lines: lines, confidence: hasTranslation ? 0.99 : 0.98)
            }
        }
        return nil
    }

    private func fetchLyrics(songMID: String) async throws -> QQLyricEnvelope {
        guard var components = URLComponents(
            string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
        ) else { throw URLError(.badURL) }
        components.queryItems = [
            URLQueryItem(name: "songmid", value: songMID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "nobase64", value: "1"),
            URLQueryItem(name: "g_tk", value: "5381")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetch(url)
        return try JSONDecoder().decode(QQLyricEnvelope.self, from: data)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 DockLyrics/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func score(_ song: QQSong, track: TrackIdentity) -> Double {
        let durationDelta = track.duration.map { abs(Double(song.interval) - $0) } ?? 0
        let title = normalized(song.songname)
        let targetTitle = normalized(track.title)
        let titlePenalty = title == targetTitle ? 0 : (title.contains(targetTitle) || targetTitle.contains(title) ? 5 : 20)
        let artists = normalized(song.singer.map(\.name).joined(separator: " "))
        let targetArtist = normalized(track.artist)
        let artistPenalty = targetArtist.isEmpty || artists.contains(targetArtist) ? 0 : 15
        return durationDelta + Double(titlePenalty + artistPenalty)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private struct QQSearchEnvelope: Decodable {
    let data: QQSearchData
}

private struct QQSearchData: Decodable {
    let song: QQSongResult
}

private struct QQSongResult: Decodable {
    let list: [QQSong]?
}

private struct QQSong: Decodable {
    let songmid: String
    let songname: String
    let interval: Int
    let singer: [QQSinger]
}

private struct QQSinger: Decodable {
    let name: String
}

private struct QQLyricEnvelope: Decodable {
    let lyric: String?
    let trans: String?
}

struct LRCLIBProvider: LyricsProvider {
    let id = "lrclib"

    func lyrics(for track: TrackIdentity) async throws -> LyricsResult? {
        guard var components = URLComponents(string: "https://lrclib.net/api/get") else { return nil }
        var queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        if let album = track.album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = track.duration {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("DockLyrics/0.1", forHTTPHeaderField: "Lrclib-Client")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let record = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
        guard !record.instrumental,
              let synced = record.syncedLyrics,
              !synced.isEmpty else { return nil }

        let lines = LRCParser.lines(original: synced, translation: nil, duration: track.duration)
        return lines.isEmpty ? nil : LyricsResult(lines: lines, confidence: 0.90)
    }
}

private struct LRCLIBRecord: Decodable {
    let instrumental: Bool
    let syncedLyrics: String?
}

struct NetEaseLyricsProvider: LyricsProvider {
    let id = "netease"

    func lyrics(for track: TrackIdentity) async throws -> LyricsResult? {
        guard var search = URLComponents(string: "https://music.163.com/api/search/get/web") else { return nil }
        search.queryItems = [
            URLQueryItem(name: "s", value: "\(track.title) \(track.artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "total", value: "true")
        ]
        guard let searchURL = search.url else { return nil }
        let searchData = try await fetch(searchURL)
        let envelope = try JSONDecoder().decode(NetEaseSearchEnvelope.self, from: searchData)
        guard let candidates = envelope.result?.songs, !candidates.isEmpty else { return nil }

        let selected = candidates.min { lhs, rhs in
            score(lhs, track: track) < score(rhs, track: track)
        }
        guard let selected, score(selected, track: track) < 45 else { return nil }

        guard var lyricURL = URLComponents(string: "https://music.163.com/api/song/lyric") else { return nil }
        lyricURL.queryItems = [
            URLQueryItem(name: "id", value: String(selected.id)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "1")
        ]
        guard let finalURL = lyricURL.url else { return nil }
        let lyricData = try await fetch(finalURL)
        let response = try JSONDecoder().decode(NetEaseLyricEnvelope.self, from: lyricData)
        guard let original = response.lrc?.lyric, !original.isEmpty else { return nil }

        let translation = response.tlyric?.lyric
        let lines = LRCParser.lines(
            original: original,
            translation: translation,
            duration: track.duration
        )
        let hasTranslation = translation?.isEmpty == false
        return lines.isEmpty ? nil : LyricsResult(
            lines: lines,
            confidence: hasTranslation ? 0.96 : 0.92
        )
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 DockLyrics/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func score(_ song: NetEaseSong, track: TrackIdentity) -> Double {
        let durationDelta = track.duration.map { abs(Double(song.duration) / 1_000 - $0) } ?? 0
        let titlePenalty = normalized(song.name) == normalized(track.title) ? 0 : 18
        let artists = song.artists.map(\.name).joined(separator: " ")
        let artistPenalty = normalized(artists).contains(normalized(track.artist)) ? 0 : 18
        return durationDelta + Double(titlePenalty + artistPenalty)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private struct NetEaseSearchEnvelope: Decodable {
    let result: NetEaseSearchResult?
}

private struct NetEaseSearchResult: Decodable {
    let songs: [NetEaseSong]?
}

private struct NetEaseSong: Decodable {
    let id: Int
    let name: String
    let duration: Int
    let artists: [NetEaseArtist]
}

private struct NetEaseArtist: Decodable {
    let name: String
}

private struct NetEaseLyricEnvelope: Decodable {
    let lrc: NetEaseLyricPayload?
    let tlyric: NetEaseLyricPayload?
}

private struct NetEaseLyricPayload: Decodable {
    let lyric: String?
}

enum LRCParser {
    private struct Entry {
        let time: TimeInterval
        let text: String
    }

    static func lines(
        original: String,
        translation: String?,
        duration: TimeInterval?
    ) -> [LyricLine] {
        let originals = entries(in: original)
        let translationEntries = entries(in: translation ?? "").filter {
            containsCJK($0.text)
        }
        let matchedTranslations = matchTranslations(
            originals: originals,
            translations: translationEntries
        )

        return originals.enumerated().map { index, entry in
            let end = index + 1 < originals.count
                ? originals[index + 1].time
                : max(duration ?? entry.time + 6, entry.time + 1)
            let candidate = matchedTranslations[index] ?? ""
            let translated = normalized(candidate) == normalized(entry.text) ? "" : candidate
            let traditional = translated.applyingTransform(
                StringTransform("Hans-Hant"),
                reverse: false
            ) ?? translated
            let simplified = translated.applyingTransform(
                StringTransform("Hant-Hans"),
                reverse: false
            ) ?? translated

            return LyricLine(
                original: entry.text,
                traditionalTranslation: traditional,
                simplifiedTranslation: simplified,
                words: [TimedWord(text: entry.text, start: entry.time, end: end)],
                start: entry.time,
                end: end
            )
        }
    }

    private static func entries(in lrc: String) -> [Entry] {
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return lrc.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges == 5,
                  let minuteRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 4), in: line),
                  let minutes = Double(line[minuteRange]),
                  let seconds = Double(line[secondRange]) else { return nil }

            var fraction = 0.0
            if let fractionRange = Range(match.range(at: 3), in: line) {
                let digits = String(line[fractionRange])
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return Entry(time: minutes * 60 + seconds + fraction, text: text)
        }
        .sorted { $0.time < $1.time }
    }

    /// Providers frequently offset translated LRC timestamps from the original.
    /// Reserve near-exact matches first, then fill remaining lines with the same
    /// relaxed tolerance used by the previous Spotify car-lyrics implementation.
    private static func matchTranslations(
        originals: [Entry],
        translations: [Entry]
    ) -> [String?] {
        var matches = Array<String?>(repeating: nil, count: originals.count)
        var used = Array(repeating: false, count: translations.count)

        for tolerance in [0.5, 3.5] {
            for originalIndex in originals.indices where matches[originalIndex] == nil {
                var bestIndex: Int?
                var bestDelta = TimeInterval.greatestFiniteMagnitude
                for translationIndex in translations.indices where !used[translationIndex] {
                    let delta = abs(originals[originalIndex].time - translations[translationIndex].time)
                    if delta <= tolerance, delta < bestDelta {
                        bestDelta = delta
                        bestIndex = translationIndex
                    }
                }
                if let bestIndex {
                    matches[originalIndex] = translations[bestIndex].text
                    used[bestIndex] = true
                }
            }
        }
        return matches
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
