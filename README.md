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
- **Server administration** — user accounts, bans, server properties, save config
- **Per-event announcement customization** — choose exactly which events get announced
- **Three sound packs** — Default, Majorly-G, Old
- **Auto-reconnect** — with last channel rejoin
- **.tt file import/export** — and tt:// link support
- **English and French localization**

## Requirements

- **macOS 14.0** or later
- **Apple Silicon** (M1, M2, M3, M4, or later)
- Echo cancellation with speaker tap requires **macOS 14.2+** (falls back to SDK-only reference on older systems)

## Building

```bash
# Debug build
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Debug build

# Release build
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Release build
```

No external dependencies to install — the TeamTalk SDK (`libTeamTalk5.dylib`) and WebRTC audio processing library (`libwebrtc-audio-processing.a`) are vendored in the `Vendor/` directory.

## Installation

The app is currently **unsigned** (no Apple Developer certificate). On first launch:

1. Move `ttaccessible.app` to `/Applications`
2. Try to open it — macOS will block it
3. Open **System Settings > Privacy & Security**
4. Find the message about TTAccessible being blocked and click **Open Anyway**
5. You only need to do this once

## Importing servers

If you already use TeamTalk on your Mac, you can import your saved servers:

1. Open TTAccessible
2. Go to **Server > Import TeamTalk Servers…**
3. Select your `TeamTalk5.ini` file (the app navigates to the right folder automatically)

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| F2 | Connect / Disconnect |
| Cmd+N | New server |
| Cmd+E | Edit server |
| Cmd+1/2/3/4 | Focus: tree / chat / message / history |
| Cmd+J | Join channel |
| Cmd+L | Leave channel |
| F5 | Change nickname |
| F6 | Change status |
| F7 / Shift+F7 | Create / Edit channel |
| Cmd+Shift+A | Toggle microphone |
| Cmd+M | Mute/unmute master volume |
| Cmd+Shift+M | Mute/unmute selected user |
| Cmd+U | Adjust user volume |
| Cmd+I | User info |
| Cmd+R | Start/stop recording |
| Cmd+K | Kick from channel |
| Cmd+Shift+K | Kick from server |
| Cmd+Shift+H | Hear myself (loopback) |
| F9 | Announce audio state |
| Cmd+, | Preferences |

## Architecture

Native **macOS AppKit app** with SwiftUI preference panes. The audio pipeline uses a custom dual-path capture engine — AVAudioEngine for the system default input device, standalone AUHAL AudioUnit for non-default devices — bypassing the TeamTalk SDK's built-in audio capture (which causes crackling on macOS). Audio is injected into the SDK via `TT_InsertAudioBlock` through a virtual sound device.

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
