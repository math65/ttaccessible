# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Debug build
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Debug build

# Release build + install to /Applications + zip artifact
./build.sh

# Launch built app (Debug)
open ~/Library/Developer/Xcode/DerivedData/ttaccessible-*/Build/Products/Debug/ttaccessible.app
```

No test suite exists. Verify changes by building and running the app manually.

## Language

The user speaks French. Respond in French when communicating. Code, comments, and commit messages stay in English.

## Architecture

**macOS AppKit app** with SwiftUI preference panes. Built for accessibility (VoiceOver). Localized in English and French.

### TeamTalk SDK

The app wraps the TeamTalk 5 C library (`Vendor/TeamTalk/libTeamTalk5.dylib`) via a bridging header. The SDK instance is a raw `UnsafeMutableRawPointer` managed by `TeamTalkConnectionController`. All SDK calls (`TT_*` functions) must happen on the serial dispatch queue `com.math65.ttaccessible.teamtalk`.

**Critical**: The app does NOT use `TT_InitSoundInputDevice` / `TT_EnableVoiceTransmission` for microphone capture because the SDK's direct audio path causes audio saturation/crackling. Instead, it uses a custom `AVAudioEngine` pipeline (`AdvancedMicrophoneAudioEngine`) that captures audio, applies DSP (gate, expander, limiter, gain), converts to Int16 PCM, and injects chunks via `TT_InsertAudioBlock` into the TeamTalk virtual sound device (`TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL`).

### Core Components

- **`TeamTalkConnectionController`** — Central orchestrator split across 9 extension files (`+Connection`, `+Audio`, `+Messaging`, `+ChannelManagement`, `+Administration`, `+SessionSnapshot`, `+SessionHistory`, `+Identity`). Manages SDK lifecycle, event polling, session state.
- **`AppDelegate`** — Implements `TeamTalkConnectionControllerDelegate`. Owns the connection controller and window lifecycle.
- **`ConnectedServerViewController`** — Main UI (AppKit) with channel tree, chat, history. Split across 7 extension files (`+ChannelActions`, `+UserActions`, `+Announcements`, `+OutlineDataSource`, `+OutlineDelegate`, `+TableViewDataDelegate`).
- **`AppPreferencesStore`** — `ObservableObject` wrapping `AppPreferences` (Codable struct in UserDefaults with 150ms debounced persistence). Mutate via `mutate { $0.property = value }`.
- **`AdvancedMicrophoneAudioEngine`** — AVAudioEngine-based capture with real-time DSP. Delivers `AdvancedMicrophoneAudioChunk` via callback. Uses `AVAudioSinkNode` to keep the input graph active (installTap alone doesn't fire callbacks without a connected consumer).

### Audio Pipeline Gotchas

**System default device**: Calling `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` on the already-active system default device corrupts AVAudioEngine's internal state — the tap silently receives no buffers. Always skip this call when the target device matches the system default.

**AVAudioSinkNode required**: `installTap` alone on `inputNode` does not fire callbacks — the input node must be connected through the audio graph. An `AVAudioSinkNode` (no-op consumer) is attached and connected to `inputNode` to keep the graph active without claiming the output device (which TeamTalk SDK uses).

**Multi-channel USB devices**: Multi-stream USB interfaces (e.g. Komplete Audio 6 MK2) only expose the first stream's channels by default via `inputNode.outputFormat(forBus: 0)`. The AUHAL audio unit must be configured to aggregate all streams by setting `kAudioUnitProperty_StreamFormat` on output scope element 1 with the full channel count from `InputAudioDeviceResolver`.

**Sample rate mismatch**: The hardware sample rate (from `inputNode.outputFormat`) may differ from `InputAudioDeviceInfo.nominalSampleRate` (from `kAudioDevicePropertyNominalSampleRate`). The capture engine overrides `targetFormat.sampleRate` to match the actual hardware rate. Any downstream consumer (e.g. `AdvancedMicrophonePreviewController`) must read the effective rate from the capture engine after start, not from the nominal device info.

**Apple AEC/VPIO removed**: The `AppleVoiceChatAudioEngine` (Voice Processing IO for echo cancellation) was removed entirely — it didn't work well. All microphone capture now goes through `AdvancedMicrophoneAudioEngine` exclusively.

### Audio Latency Profile (measured)

The app-side audio pipeline adds **< 0.3 ms** from DSP completion to `TT_InsertAudioBlock`. Breakdown: DSP ~0 ms, `queue.async` hop ~0.02 ms, SDK insert ~0.03 ms. The dominant capture latency is the tap buffer size (~100 ms at 44100 Hz / 4410 samples), determined by the codec's `txIntervalMSec`. Any perceived latency beyond that comes from the Opus codec, network, or server-side processing — not from the app pipeline.

### Threading Model

- `TeamTalkConnectionController` uses a serial `DispatchQueue` for all SDK operations. Public methods dispatch to this queue internally.
- `@MainActor` is used for delegate callbacks and UI-facing properties.
- Audio callbacks from `AVAudioEngine` run on the real-time audio thread — no heap allocations, no locks beyond the state snapshot pattern.
- Audio chunks are dispatched from the real-time thread to the TeamTalk queue via a single `queue.async` hop. This is the only thread transition in the capture path.

### Extension File Convention

Large classes are split into `ClassName+Responsibility.swift` files. Swift does not allow `private` access across files — shared members use `internal` (no access modifier keyword).

### Localization

```swift
L10n.text("key")              // NSLocalizedString wrapper
L10n.format("key", arg1, ...) // String(format:) wrapper
```

String files: `App/ttaccessible/en.lproj/Localizable.strings`, `fr.lproj/Localizable.strings`.

### App Sandbox

The app is sandboxed. File I/O goes to `~/Library/Containers/com.math65.ttaccessible/`. Diagnostics logs are in the Caches subdirectory.

### Original TeamTalk Reference

The original Qt/C++ TeamTalk client is at `../ttoriginal/Client/qtTeamTalk/`. Key reference files: `mainwindow.cpp` (features), `utilsound.cpp` (audio init). The original uses `TT_InitSoundInputDevice` + `TT_EnableVoiceTransmission` (direct SDK path) — we cannot use this due to audio saturation.

### Missing Features (vs original Qt client)

- **Recording** — record conversations to disk (`TT_SetUserRecordingState` not implemented)
- **Channel Operator** — assign channel operator (`TT_DoChannelOp` not wired)
- **Hear Myself** — subscribe to own voice via `TT_DoSubscribe(SUBSCRIBE_VOICE, myUserID)` (original uses Ctrl+Shift+4). The subscription mechanism exists but no dedicated action/shortcut.
- **Video/Desktop/Media streaming** — not implemented (low priority for accessibility)
