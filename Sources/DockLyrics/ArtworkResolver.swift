import Foundation

struct ArtworkResolver: Sendable {
    func artworkURL(for snapshot: SpotifySnapshot) async -> URL? {
        if let direct = snapshot.artworkURL { return direct }

        if snapshot.trackID.hasPrefix("spotify:track:"),
           let spotify = await spotifyOEmbedURL(for: snapshot.trackID) {
            return spotify
        }

        return await netEaseArtworkURL(
            title: snapshot.title,
            artist: snapshot.artist,
            duration: snapshot.duration
        )
    }

    private func spotifyOEmbedURL(for trackID: String) async -> URL? {
        let id = trackID.replacingOccurrences(of: "spotify:track:", with: "")
        guard var components = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://open.spotify.com/track/\(id)")
        ]
        guard let url = components.url,
              let data = try? await fetch(url),
              let response = try? JSONDecoder().decode(SpotifyOEmbed.self, from: data) else {
            return nil
        }
        return URL(string: response.thumbnailURL)
    }

    private func netEaseArtworkURL(
        title: String,
        artist: String,
        duration: TimeInterval
    ) async -> URL? {
        guard var search = URLComponents(string: "https://music.163.com/api/search/get/web") else { return nil }
        search.queryItems = [
            URLQueryItem(name: "s", value: "\(title) \(artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let searchURL = search.url,
              let searchData = try? await fetch(searchURL),
              let envelope = try? JSONDecoder().decode(ArtworkSearchEnvelope.self, from: searchData),
              let songs = envelope.result?.songs,
              let song = songs.min(by: {
                  abs(Double($0.duration) / 1_000 - duration)
                      < abs(Double($1.duration) / 1_000 - duration)
              }),
              abs(Double(song.duration) / 1_000 - duration) < 12,
              var detail = URLComponents(string: "https://music.163.com/api/song/detail/") else {
            return nil
        }

        detail.queryItems = [URLQueryItem(name: "ids", value: "[\(song.id)]")]
        guard let detailURL = detail.url,
              let detailData = try? await fetch(detailURL),
              let response = try? JSONDecoder().decode(ArtworkDetailEnvelope.self, from: detailData),
              let value = response.songs.first?.album.picURL else {
            return nil
        }
        return URL(string: value)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 DockLyrics/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct SpotifyOEmbed: Decodable {
    let thumbnailURL: String

    enum CodingKeys: String, CodingKey {
        case thumbnailURL = "thumbnail_url"
    }
}

private struct ArtworkSearchEnvelope: Decodable {
    let result: ArtworkSearchResult?
}

private struct ArtworkSearchResult: Decodable {
    let songs: [ArtworkSearchSong]?
}

private struct ArtworkSearchSong: Decodable {
    let id: Int
    let duration: Int
}

private struct ArtworkDetailEnvelope: Decodable {
    let songs: [ArtworkDetailSong]
}

private struct ArtworkDetailSong: Decodable {
    let album: ArtworkAlbum
}

private struct ArtworkAlbum: Decodable {
    let picURL: String

    enum CodingKeys: String, CodingKey {
        case picURL = "picUrl"
    }
}
