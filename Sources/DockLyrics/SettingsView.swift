import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        TabView {
            Form {
                LabeledContent("播放器") {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(model.isUsingSpotify ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(model.spotifyState.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("介面語言", selection: $model.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }

                Picker("歌詞顯示", selection: $model.displayMode) {
                    ForEach(LyricDisplayMode.allCases) { mode in
                        Text(localized(mode)).tag(mode)
                    }
                }

                Toggle("顯示歌曲資訊", isOn: $model.showSongInfo)
                Toggle("外語歌曲自動顯示中文翻譯", isOn: .constant(true))
                    .disabled(true)
            }
            .formStyle(.grouped)
            .tabItem { Label("一般", systemImage: "gearshape") }

            Form {
                Picker("外觀", selection: $model.appearance) {
                    ForEach(AppearanceMode.allCases) { appearance in
                        Text(localized(appearance)).tag(appearance)
                    }
                }

                Toggle("毛玻璃模糊", isOn: $model.blurEnabled)
                LabeledContent("背景透明度") {
                    Slider(value: $model.backgroundOpacity, in: 0.35...0.95)
                        .frame(width: 220)
                }
                LabeledContent("歌詞大小") {
                    Slider(value: $model.fontScale, in: 0.78...1.22)
                        .frame(width: 220)
                }

                Toggle("從封面自動取色", isOn: $model.useArtworkAccent)
                ColorPicker("逐字高亮顏色", selection: $model.accentColor)
                    .disabled(model.useArtworkAccent)
            }
            .formStyle(.grouped)
            .tabItem { Label("外觀", systemImage: "paintpalette") }

            Form {
                LabeledContent("歌詞服務") {
                    Text("自動選擇")
                        .foregroundStyle(.secondary)
                }
                LabeledContent(localizedLyricTimingTitle) {
                    HStack(spacing: 10) {
                        Slider(value: $model.lyricOffset, in: -1...1, step: 0.05)
                            .frame(width: 185)
                        Text(String(format: "%+.2f s", model.lyricOffset))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                        Button(localizedReset) { model.lyricOffset = 0.12 }
                    }
                }
                Text(localizedLyricTimingHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("目前歌曲由 Spotify for Mac 提供。主畫面不會顯示歌詞來源；正式版將透過可替換的供應器依序匹配同步歌詞與翻譯。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("歌詞", systemImage: "text.quote") }

        }
        .padding(12)
        .frame(width: 520, height: 370)
    }

    private func localized(_ mode: LyricDisplayMode) -> String {
        guard model.interfaceLanguage == .simplified else { return mode.rawValue }
        return switch mode {
        case .bilingual: "双语"
        case .original: "仅原文"
        case .translation: "仅译文"
        }
    }

    private func localized(_ appearance: AppearanceMode) -> String {
        guard model.interfaceLanguage == .simplified else { return appearance.rawValue }
        return switch appearance {
        case .automatic: "自动"
        case .dark: "深色"
        case .light: "浅色"
        }
    }

    private var localizedLyricTimingTitle: String {
        model.interfaceLanguage == .traditional ? "歌詞時間微調" : "歌词时间微调"
    }

    private var localizedLyricTimingHelp: String {
        model.interfaceLanguage == .traditional
            ? "預設提前 0.12 秒，與車機版一致。正值讓歌詞更早顯示，負值讓歌詞更晚顯示。"
            : "默认提前 0.12 秒，与车机版一致。正值让歌词更早显示，负值让歌词更晚显示。"
    }

    private var localizedReset: String {
        model.interfaceLanguage == .traditional ? "重設" : "重置"
    }
}
