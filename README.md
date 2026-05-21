# TTAccessible

A native, fully accessible TeamTalk client for macOS, built with VoiceOver as a first-class citizen.

The official TeamTalk Qt client on Mac has significant accessibility issues — broken navigation, unresponsive context menus, audio crackling, and sluggish VoiceOver announcements. TTAccessible is a from-scratch alternative that puts screen reader users first.

## Features

- **Full VoiceOver support** — every window, menu, control, and navigation flow is built for screen readers
- **Full keyboard navigation** — Cmd+1/2/3/4 for UI areas, F5/F6/F7 for identity and channels, and many more
- **Native macOS interface** — real AppKit + SwiftUI, not a cross-platform wrapper
- **Channel browsing and joining** — tree view with users, subchannels, topics
- **Channel and private chat** — with clickable links and VoiceOver announcements
- **File sharing** — upload/download with progress, speed, ETA
- **Advanced audio engine** — custom dual-path capture (AVAudioEngine + standalone AUHAL), input gain, channel selection, echo cancellation
- **WebRTC AEC3 echo cancellation** — with real speaker output capture via Core Audio taps (macOS 14.2+), cancels VoiceOver and system sounds
- **Adaptive jitter buffer** — improves audio quality on unstable connections
- **Recording** — muxed (all voices) or per-user, WAV or OGG format, auto-restart on channel change
- **Per-user volume and stereo balance** — persisted across sessions
- **In-window video** — media file streaming with collapsible panel (the TeamTalk SDK bundles FFmpeg for playback; a system `ffmpeg` binary is only needed to pre-convert files the SDK cannot open)
- **Server administration** — user accounts, bans, server properties, save config
- **Per-event announcement customization** — choose exactly which events get announced
- **Three sound packs** — Default, Majorly-G, Old
- **Auto-reconnect** — with last channel rejoin
- **.tt file import/export** — and tt:// link support
- **Automatic updates** — signed and notarized releases delivered in-app via [Sparkle](https://sparkle-project.org)
- **English and French localization**

## Requirements

- **macOS 14.0** or later
- **Apple Silicon** (M1, M2, M3, M4, or later)
- Echo cancellation with speaker tap requires **macOS 14.2+** (falls back to SDK-only reference on older systems)

## Building

### Prerequisites

- Xcode (with command line tools)
- [p7zip](https://formulae.brew.sh/formula/p7zip) — `brew install p7zip`
- [ffmpeg](https://formulae.brew.sh/formula/ffmpeg) (optional) — `brew install ffmpeg` — only for pre-converting media files the SDK cannot open; streaming itself uses the SDK's bundled FFmpeg

### Setup

The TeamTalk SDK binary is not included in the repository. Download it before building:

```bash
./scripts/download-sdk.sh
```

This downloads `libTeamTalk5.dylib` and `TeamTalk.h` from the [official TeamTalk SDK](https://www.bearware.dk/?page_id=419) and places them in `Vendor/TeamTalk/`.

### Build

For development:

```bash
# Debug build
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Debug build

# Release build
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Release build
```

To produce a local Release `.app` and zip without signing:

```bash
./build.sh
```

Packaging signed and notarized releases (publishing to GitHub, updating the Sparkle appcast) is maintainer-only and requires a `Developer ID Application` certificate.

## Installation

1. Download the latest `ttaccessible-*.zip` from the [GitHub releases page](https://github.com/math65/ttaccessible/releases).
2. Unzip and drag `ttaccessible.app` into `/Applications`.
3. Double-click to launch.

The app is signed with a Developer ID certificate and notarized by Apple, so no Gatekeeper prompt appears on first launch. Subsequent updates are delivered automatically in-app via Sparkle — you can also trigger a check manually from **ttaccessible > Check for updates…**.

## Importing servers

If you already use TeamTalk on your Mac, you can import your saved servers:

1. Open TTAccessible
2. Go to **Server > Import TeamTalk Servers…**
3. Select your `TeamTalk5.ini` file (the app navigates to the right folder automatically)

## Keyboard shortcuts

### Application & navigation

| Shortcut | Action |
|----------|--------|
| Cmd+, | Preferences |
| F2 | Connect / Disconnect |
| Cmd+N | New server |
| Cmd+E | Edit server (server list) / Open private messages (connected) |
| Cmd+Shift+I | Import TeamTalk servers (server list) / Server stats (connected) |
| Cmd+1/2/3/4 | Focus: tree / chat / message / history |

### Identity & channels

| Shortcut | Action |
|----------|--------|
| F5 | Change nickname |
| Shift+F5 | Upload file |
| F6 | Change status |
| F7 / Shift+F7 | Create / Edit channel |
| F8 | Delete channel |
| Cmd+J | Join channel |
| Cmd+L | Leave channel |

### Messages, files & sharing

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+E | Open private messages |
| Cmd+Shift+F | Open channel files |
| Cmd+Shift+S | Export chat to file |
| Cmd+Shift+L | Copy server link |

### Audio

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+A | Toggle microphone |
| Cmd+M | Mute / unmute master volume |
| Cmd+Shift+H | Hear myself (loopback) |
| Cmd+R | Start / stop recording |
| F9 | Announce audio state |

### User actions

| Shortcut | Action |
|----------|--------|
| Cmd+I | User info |
| Cmd+U | Adjust user volume & stereo |
| Cmd+Shift+M | Mute / unmute selected user |
| Ctrl+Cmd+Shift+M | Mute / unmute user's media file |
| Ctrl+Cmd+O | Toggle channel operator |
| Cmd+K | Kick from channel |
| Cmd+Shift+K | Kick from server |
| Cmd+Option+X | Move user to channel |

### Administration

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+U | User accounts |
| Cmd+Shift+B | Banned users |
| Cmd+Shift+P | Server properties |
| Cmd+B | Broadcast message |

### Media streaming

| Shortcut | Action |
|----------|--------|
| Cmd+Option+S | Stream media from file |
| Cmd+Option+U | Stream media from URL |
| Cmd+Option+. | Stop media streaming |

## Architecture

Native **macOS AppKit app** with SwiftUI preference panes. The audio pipeline uses a custom AUHAL capture engine (explicit CoreAudio device binding for every input, including system default) bypassing the TeamTalk SDK's built-in audio capture (which causes crackling on macOS). Captured PCM is resampled to the channel codec rate before injection via `TT_InsertAudioBlock` through a virtual sound device.

Echo cancellation uses WebRTC AEC3 (from `webrtc-audio-processing` v2.0, WebRTC M131) with the actual speaker output captured via Core Audio taps as the reference signal — not just the decoded TeamTalk audio. This allows cancellation of VoiceOver, system sounds, and all other audio.

## Development

This project is developed with the help of [Claude](https://claude.ai/code) (Anthropic's AI coding assistant). Claude helps with SDK integration, audio engine development, bug detection, and code review. All design decisions, testing, and direction are human-driven.

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

### Third-party components

- **TeamTalk 5 SDK** — proprietary, see [BearWare](https://bearware.dk) for licensing terms
- **WebRTC audio processing** — BSD-style license, from [freedesktop.org](https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing)
- **Abseil C++** — Apache 2.0 license

## Acknowledgments

Thanks to the beta testers on [AppleVis](https://www.applevis.com) for their invaluable feedback — Johann, Casey, Dan, Matthew, Quinton, John, Herbie, and everyone else who took the time to test and report issues. This app wouldn't be what it is without you.
