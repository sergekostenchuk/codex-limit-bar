# Codex Limit Bar

A small native macOS menu bar utility that shows the latest Codex usage limits recorded by the local Codex app.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License MIT](https://img.shields.io/badge/license-MIT-blue)

## Features

- Displays remaining usage for the five-hour and seven-day windows.
- Shows the local reset time for each window.
- Refreshes once per minute with a 10-second timer leeway.
- Refreshes after the Mac wakes from sleep.
- Stores the last known snapshot for offline display.
- Supports launch at login through `SMAppService`.
- Uses a compact native AppKit status item.
- Does not read, store, or transmit Codex credentials.

## How it works

Codex writes structured `rate_limits` events to JSONL session files under:

```text
~/.codex/sessions
~/.codex/archived_sessions
```

Codex Limit Bar checks only recently modified JSONL files and reads at most the last 4 MB of each candidate. All processing happens locally.

The displayed value is the latest snapshot written by Codex. If Codex has not produced a recent event, the app marks the value as saved rather than live.

## Requirements

- macOS 13 Ventura or newer
- A local Codex installation that writes session events to `~/.codex`
- Xcode 16 or newer to build from source

## Build from source

1. Clone the repository.
2. Open `CodexLimitBar.xcodeproj` in Xcode.
3. Select your development team under Signing & Capabilities if you want a signed local build.
4. Run the `CodexLimitBar` scheme.

Command-line build without code signing:

```sh
xcodebuild \
  -project CodexLimitBar.xcodeproj \
  -scheme CodexLimitBar \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run tests:

```sh
xcodebuild \
  -project CodexLimitBar.xcodeproj \
  -scheme CodexLimitBar \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The source package is also mirrored on npm:

```sh
npm pack codex-limit-bar
```

The npm package contains the Xcode source project; it is not a Node.js runtime or a prebuilt macOS application.

## Privacy

The app has no networking code and does not access Codex authentication files or the macOS Keychain. See [SECURITY.md](SECURITY.md) for reporting security issues.

## Limitations

- Codex's local session format is not a guaranteed public API and may change.
- Values update after Codex writes a new rate-limit event.
- The app intentionally runs without App Sandbox so it can read `~/.codex` automatically.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

MIT © 2026 Sergey Kosten. See [LICENSE](LICENSE).
