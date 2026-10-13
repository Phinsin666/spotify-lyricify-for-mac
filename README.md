<p align="center">
  <img src="Sources/DockLyrics/Resources/AppIcon.png" width="128" height="128" alt="Spotify Lyricify for Mac icon">
</p>

<h1 align="center">Spotify Lyricify for Mac</h1>

<p align="center">A lightweight, Dock-height synchronized lyrics overlay for Spotify on macOS.</p>

<p align="center">
  <strong>English</strong> | <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
  <a href="https://github.com/Phinsin666/spotify-lyricify-for-mac/releases"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/Phinsin666/spotify-lyricify-for-mac"></a>
</p>

> **Tip:** The app works especially well when the macOS Dock is set to automatically hide and show.

![Spotify Lyricify for Mac](docs/screenshot.png)

Spotify Lyricify for Mac keeps the current lyric visible in a compact floating bar designed around the height and visual rhythm of the macOS Dock. The app uses a Traditional Chinese interface by default and can be switched to Simplified Chinese in Settings.

## Features

- Reads the current track, artist, album, playback position, and state from Spotify for Mac
- Matches synchronized lyrics across QQ Music, NetEase Cloud Music, and LRCLIB
- Displays the original line with a provider-supplied Chinese translation for foreign-language songs
- Displays the current and next line for Chinese songs
- Supports Traditional and Simplified Chinese
- Automatically scrolls long track titles
- Resolves and displays album artwork
- Supports automatic, light, and dark appearances
- Offers font scale, opacity, blur, and accent-color customization
- Provides a borderless floating window with mouse dragging and macOS three-finger drag support
- Can appear across Spaces and alongside full-screen apps
- Includes a Dock icon and menu bar playback controls

## Requirements

- macOS 14 Sonoma or later
- Spotify for Mac
- Xcode 16 or Swift 6-compatible command-line tools when building from source

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/Phinsin666/spotify-lyricify-for-mac/releases/latest).
2. Open the disk image.
3. Drag **Spotify Lyricify for Mac** into the **Applications** folder.
4. Launch the app from Applications.

The downloadable build is ad-hoc signed but not Apple-notarized. If macOS blocks the first launch, right-click the app in Finder, choose **Open**, and confirm once. Do not bypass security warnings for copies downloaded from anywhere other than this repository.

On first launch, macOS may ask for permission to control Spotify. This permission is used only to read now-playing information and perform play/pause, previous-track, and next-track actions. You can manage it under **System Settings → Privacy & Security → Automation**.

## Usage

1. Open Spotify and start playing a track.
2. Launch Spotify Lyricify for Mac.
3. The lyrics bar appears near the bottom of the screen and can be dragged anywhere.
4. Select the `…` button on the right side of the bar to open Settings.
5. Use the menu bar icon to restore the lyrics window, control Spotify, or quit the app.

If you use a menu bar organizer, the new status icon may initially appear in its hidden section. Expand that section and Command-drag the icon into the always-visible area.

## Lyrics and translations

The app compares matching results from multiple lyrics providers and prefers a result containing usable Chinese line-by-line translations. Translations come from the lyrics provider; song content is not uploaded to a generative AI service.

Synchronized lyrics or translations are not available for every track. Regional releases, remixes, metadata differences, and provider availability can affect matching. This project does not host or distribute a lyrics database.

## Development

Run directly with Swift Package Manager:

```bash
swift run DockLyrics
```

Or open `Package.swift` in Xcode.

Build and package a local application bundle:

```bash
swift build
swift build -c release
./scripts/build-app.sh
./scripts/build-dmg.sh
```

The packaging scripts create an ad-hoc signed `.app` and `.dmg` inside `dist/`. Fully trusted public distribution still requires the maintainer's own Apple Developer certificate and notarization.

## Project structure

```text
Sources/DockLyrics/
├── DockLyricsApp.swift           # App, floating window, and menu bar entry
├── PlaybackModel.swift           # Playback state and lyric timeline
├── SpotifyNowPlayingClient.swift # Local Spotify AppleScript integration
├── LyricsProvider.swift          # Provider lookup, ranking, and translation matching
├── ArtworkResolver.swift         # Album artwork resolution
├── LyricsBarView.swift           # Floating lyrics interface
└── SettingsView.swift            # Appearance and language settings
```

## Privacy

- No Spotify Web API client ID is required.
- The app does not collect account information, listening history, or personal data.
- Spotify playback information is read locally through AppleScript.
- Track title, artist, album, and duration are sent to lyrics services only to find a matching result.

## Contributing

Issues and pull requests are welcome. Before submitting a change, make sure `swift build` succeeds and keep interface text compatible with both Traditional and Simplified Chinese whenever possible. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Disclaimer

Spotify Lyricify for Mac is an unofficial open-source project and is not affiliated with, endorsed by, or sponsored by Spotify, Lyricify, Tencent Music, or NetEase Cloud Music. Spotify, QQ Music, NetEase Cloud Music, Lyricify, and related marks belong to their respective owners. Lyrics and translations remain the property of their respective authors and rights holders. Please comply with applicable laws and the terms of the relevant services.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Phinsin666/spotify-lyricify-for-mac&type=Date)](https://star-history.com/#Phinsin666/spotify-lyricify-for-mac&Date)

## Support the Project

Spotify Lyricify for Mac is free and open source. If it helps you, consider starring the repository. Donations are entirely optional and do not constitute a purchase, subscription, or service commitment.

<table>
  <tr>
    <th>Alipay</th>
    <th>WeChat Pay</th>
  </tr>
  <tr>
    <td><img src="docs/donate-alipay.jpg" alt="Alipay donation QR code" width="360"></td>
    <td><img src="docs/donate-wechat.jpg" alt="WeChat Pay donation QR code" width="360"></td>
  </tr>
</table>

## License

[MIT](LICENSE)
