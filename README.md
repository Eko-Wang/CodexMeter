# CodexMeter

Native macOS app and desktop widgets for Codex limits and official account token activity.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- Codex/ChatGPT signed in on this Mac (`~/.codex/auth.json` exists)

## Run

1. Open `CodexMeter.xcodeproj` in Xcode.
2. Select the **CodexMeter** scheme and your Mac.
3. Run the app once, then add **CodexMeter** from the macOS widget gallery.

The host app registers itself as a macOS login item, reads the current Codex login locally, refreshes limits every minute, and mirrors a sanitized snapshot into the widget sandbox. The login item can be disabled in **System Settings → General → Login Items**. Credentials are never copied into the project, widget, or logs.
