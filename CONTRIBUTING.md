# Contributing

Thank you for contributing to Spotify Lyricify for Mac.

## Getting started

1. Fork the repository and create a focused feature branch.
2. Run `swift build` to verify that the project compiles.
3. Keep each change limited to one clear purpose and describe how it was tested.
4. Open a pull request.

## Code and interface guidelines

- Support macOS 14 and later.
- Do not commit API keys, user data, lyric caches, or build artifacts.
- Consider both Traditional and Simplified Chinese when adding interface copy.
- A lyrics-provider failure must not block the UI or Spotify playback controls.
- Do not log a user's complete listening history.

## Reporting an issue

Include the macOS version, Spotify version, track name, reproduction steps, and a redacted screenshot when useful. Do not upload account details or sensitive content from system privacy settings.

---

## 中文

感谢你愿意为 Spotify Lyricify for Mac 做贡献。

1. Fork 本仓库并创建目标明确的功能分支。
2. 使用 `swift build` 确认项目可编译。
3. 尽量将修改限制在单一目的，并说明测试方式。
4. 提交 Pull Request。

请勿提交 API 密钥、用户数据、歌词缓存或构建产物。新增界面文本时，请同时考虑繁体与简体中文。报告问题时请提供 macOS 版本、Spotify 版本、歌曲名称、复现步骤和必要的脱敏截图。
