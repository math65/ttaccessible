# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build Commands

```bash
# Debug build (CLI)
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Debug build

# Run the unit-test suite (ttaccessibleTests target)
xcodebuild test -project App/ttaccessible.xcodeproj -scheme ttaccessible -destination 'platform=macOS'

# Launch built app (Debug)
open ~/Library/Developer/Xcode/DerivedData/ttaccessible-*/Build/Products/Debug/ttaccessible.app

# Release build + zip artifact (staged for Sparkle appcast)
./build.sh

# Release + Developer ID sign + notarize + staple
./build.sh --notarize

# Same as --notarize, plus push a draft GitHub release
./build.sh --release

# Beta-channel release: appcast item tagged <sparkle:channel>beta</sparkle:channel>
# (only delivered to users who enabled "Include beta versions") + GitHub prerelease
./build.sh --release --beta

# Regenerate the Apple Help Book after editing Help/Source/**.md
./scripts/build-help-book.sh <marketing-version> <build-number>
./scripts/build-help-book.sh --dev     # timestamp version, defeats the helpd cache
```

`build.sh` re-signs the Xcode-built .app with the `Developer ID Application` cert (the project itself still builds with Apple Development for convenience). Requires the notarytool keychain profile `ttaccessible-notary` to be stored (see notarization setup memory).

An XCTest unit-test target (`ttaccessibleTests`, file-system synchronized group) covers
pure/deterministic logic only: the gain dB↔% and user-volume↔% curves, `clampGainDB`, and
Codable migrations of preference structs. Run via the `xcodebuild test` command above.

The tests deliberately do NOT touch AppKit UI, CoreAudio, or the TeamTalk SDK runtime —
verify those by building and running the app manually.

## Language

The user speaks French. Respond in French when communicating. Code, comments, and commit messages stay in English.

## Architecture

**macOS AppKit app** with SwiftUI preference panes. Built for accessibility (VoiceOver). Localized in English and French.

### TeamTalk SDK

The app wraps the TeamTalk 5 C library (`Vendor/TeamTalk/libTeamTalk5.dylib`) via a bridging header. The SDK instance is a raw `UnsafeMutableRawPointer` managed by `TeamTalkConnectionController`. All SDK calls (`TT_*` functions) must happen on the serial dispatch queue `com.math65.ttaccessible.teamtalk`.

**PortAudio probe patch (mandatory, applied at build time)**: The vendored dylib is binary-patched by `scripts/patch-sdk-portaudio.py` so PortAudio's `IsFormatSupported()` returns immediately — this removes the ~13 s startup device probe (`TT_InitTeamTalkPoll` opening/closing a CoreAudio stream per device × per standard rate). Safe because the app only ever uses the TeamTalk virtual device, never a real PortAudio device. The patcher is symbol-driven, idempotent, and fail-loud (aborts if the prologue isn't a known-good unpatched or already-patched byte sequence). It runs in TWO places: (1) `scripts/download-sdk.sh` after a fresh download, and (2) a **`Patch TeamTalk SDK (PortAudio probe)`** run-script build phase (first in the app target, before Sources/Embed — PR #27) so no build can ship an unpatched dylib regardless of how the gitignored dylib landed on the machine. **beta.9 and earlier shipped an unpatched dylib** because the patch was only coupled to a fresh download; the build phase is the permanent fix (first shipped in beta.10). If a future SDK bump changes the `_IsFormatSupported` prologue, the patcher aborts the build — update `ORIGINAL_PROLOGUES` in the script after verifying the new bytes by hand.

**Documented exceptions to the serial-queue rule** (both rely on the SDK's per-instance internal locking, validated in the field — not a violation):
- **Prewarm** (`+Connection`): a new instance is created on a background queue (`TT_InitTeamTalkPoll`) to hide the sound-system probe latency.
- **`AudioBlockPump`** (PR #26, beta.9): per-user voice/media audio blocks are drained via `TT_AcquireUserAudioBlock` / `TT_ReleaseUserAudioBlock` on the pump's own 10 ms user-interactive timer queue, NOT the message loop. Rationale: acquiring blocks inside the 20 ms message-loop drain shared the serial queue with channel-tree publish/history/state work, so one slow tick in a crowded channel starved every mix source at once (choppy for everyone, zero ring underflows). The muxed AEC-reference stream (pre-14.2 fallback) stays on the message loop. `stop()` is synchronous (`queue.sync`) so no acquire is in flight when the instance is torn down.

**Critical**: The app does NOT use `TT_InitSoundInputDevice` / `TT_EnableVoiceTransmission` for microphone capture because the SDK's direct audio path causes audio saturation/crackling. Instead, it uses a dual-path capture engine (`AdvancedMicrophoneAudioEngine`) that captures audio, applies input gain, converts to Int16 PCM, and injects chunks via `TT_InsertAudioBlock` into the TeamTalk virtual sound device (`TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL`).

### Core Components

- **`TeamTalkConnectionController`** — Central orchestrator split across 11 extension files (`+Connection`, `+Audio`, `+Messaging`, `+ChannelManagement`, `+Administration`, `+SessionSnapshot`, `+SessionHistory`, `+SessionGuard`, `+Identity`, `+MediaStreaming`, `+Video`). Manages SDK lifecycle, event polling, session state, media file streaming, and stale-session healing during auto-reconnect. `+SessionGuard` surfaces a clean disconnect when the UI still shows a connected server but the SDK instance is gone (e.g. mid auto-reconnect). `+MediaStreaming` / `+Video` wrap `TT_StartStreamingMediaFileToChannel` and media-file probing for audio/video playback into channels.
- **`AppDelegate`** — Implements `TeamTalkConnectionControllerDelegate`. Owns the connection controller and window lifecycle. Handles global audio device change events.
- **`ConnectedServerViewController`** — Main UI (AppKit) with channel tree, chat, history. Split across 6 extension files (`+ChannelActions`, `+UserActions`, `+Announcements`, `+OutlineDataSource`, `+OutlineDelegate`, `+TableViewDataDelegate`).
- **`AppPreferencesStore`** — `ObservableObject` wrapping `AppPreferences` (Codable struct in UserDefaults with 150ms debounced persistence). Mutate via `mutate { $0.property = value }`.
- **`AdvancedMicrophoneAudioEngine`** — Dual-path audio capture engine. Uses AVAudioEngine for the system default input device, and a standalone AUHAL AudioUnit for non-default devices (virtual devices, loopback, etc.). Delivers `AdvancedMicrophoneAudioChunk` via callback.

### Audio Pipeline

The audio pipeline with optional echo cancellation:
```
Microphone → [AVAudioEngine OR standalone AUHAL] → Float32 PCM → interleave → gain → Int16 PCM → [WebRTC AEC3] → TT_InsertAudioBlock → TeamTalk SDK
                                                                                                        ↑
                                                                                          TT_MUXED_USERID speaker reference (resampled to capture rate)
```

**Dual capture paths** (since beta 9):
- **System default device** → AVAudioEngine path: `inputNode → mixerNode → sinkNode` with tap on mixer. AVAudioEngine cannot reliably switch to non-default devices (it creates a `CADefaultDeviceAggregate` locked to the default device's format).
- **Non-default devices** → Standalone AUHAL path: `AudioComponentInstanceNew(kAudioUnitSubType_HALOutput)` → enable input IO on element 1 → disable output IO on element 0 → set device → set Float32 non-interleaved output format → input callback → `AudioUnitRender`. This gives full control over device selection, sample rate, and channel count without the aggregate device interference.

**AUHAL frame accumulation**: The AUHAL callback delivers small chunks (e.g. 1024 frames at 44100 Hz = ~23ms). These are accumulated in a pre-allocated buffer until ~40ms worth of frames are collected, then processed as a single batch. This ensures clean resampling in the TeamTalk SDK (1764 frames at 44100 Hz → 1920 frames at 48000 Hz = exact integer conversion). Without accumulation, fractional frame counts cause audible crackling.

**AUHAL buffer allocation**: The `AudioBufferList` for the AUHAL render callback must be allocated with `UnsafeMutableRawPointer.allocate(byteCount:)` using the exact size for N channels: `MemoryLayout<AudioBufferList>.size + max(0, N-1) * MemoryLayout<AudioBuffer>.size`. Do NOT use `UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)` — this only allocates space for 1 AudioBuffer, and writing to additional buffers corrupts the heap.

**WebRTC AEC3 echo cancellation** (optional, toggle in Preferences > Audio):
- Uses `webrtc-audio-processing` v2.0 (WebRTC M131) from freedesktop.org, compiled as a static library (`Vendor/WebRTC/libwebrtc-audio-processing.a`, 5.4 MB).
- C++ API bridged to Swift via an Objective-C++ wrapper (`WebRTCEchoCanceller.mm` → `WebRTCEchoCanceller.h` → bridging header).
- **Reference signal** (far-end/speakers):
  - **macOS 14.2+ (default)**: `SpeakerTapCapture` (in `App/ttaccessible/Services/`) creates a Core Audio process tap via `AudioHardwareCreateProcessTap` + private aggregate device, capturing the actual mixed system output. This means VoiceOver, system sounds, media apps, and TeamTalk audio are ALL in the reference and can be cancelled. Creating the aggregate device fires `kAudioHardwarePropertyDevices`; `suppressDeviceChangeUntil` (~2 s) prevents a restart loop.
  - **Fallback** (older macOS or tap failure): `TT_EnableAudioBlockEvent(TT_MUXED_USERID)` → `CLIENTEVENT_USER_AUDIOBLOCK` → `feedReference()`. Only contains TeamTalk audio — VoiceOver and system sounds are NOT cancelled in this mode.
  - See `TeamTalkConnectionController+Audio.swift` (`startSpeakerTapForAEC`).
- **Reference signal resampling**: `feedReference()` resamples via linear interpolation when the reference rate (hardware rate from the tap, or codec rate from MUXED fallback — e.g. 48000 Hz for Opus) differs from the AEC operating rate (hardware capture rate, e.g. 44100 Hz).
- Capture signal (near-end/mic) processed via `processCapture()` in 10ms Int16 PCM frames.
- AEC3 handles delay estimation, double-talk detection, and echo suppression internally. With the speaker tap, `set_stream_delay_ms(0)` is called (near-zero delay).
- WebRTC APM noise suppression is enabled (moderate level) — helps AEC convergence.
- `renderAccumulator` is capped to ~2 seconds to prevent unbounded growth from network bursts.
- `processCapture` never allocates on the real-time thread — drops input if pre-allocated buffers are exceeded.
- Diagnostics: every 5 s, `EchoCanceller` logs config rate/channels, reference/capture rates, cumulative frame counts. Check `audio.log` for `AEC diag:` entries.

**`TT_EnableAudioBlockEventEx` does NOT work**: Tried migrating to the Ex variant with `AudioFormat` for SDK-side resampling. Failed because `effectiveSampleRate` returned the codec rate (48000) instead of the hardware rate (44100) at call time. Reverted to `TT_EnableAudioBlockEvent` for the fallback path.

**No custom DSP, no Audio Unit plugins** — gate/expander/limiter and AU chain were removed intentionally. The user preferred a clean passthrough (AEC excepted).

**No app audio capture** — the ScreenCaptureKit/CATapDescription app audio capture feature was removed entirely.

### Audio Device Hot-Plug

- `AudioDeviceChangeMonitor` listens to CoreAudio property changes (`kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultInputDevice`, `kAudioHardwarePropertyDefaultOutputDevice`) and posts `audioDevicesDidChange` on the main thread.
- **AppDelegate** observes this notification (with 500ms debounce) and calls `restartSoundSystem()` which: stops the mic engine, closes the virtual input, calls `TT_RestartSoundSystem()` (forces PortAudio to re-enumerate), re-opens the output device, and restarts the mic engine if it was active. Without `TT_RestartSoundSystem()`, `TT_GetSoundDevices()` returns stale entries.
- **AudioPreferencesStore** also observes the notification (with 500ms debounce) to refresh the UI device list.
- `restartSoundSystem()` has an `isRestartingSoundSystem` guard to prevent re-entrant calls from both handlers.

### Audio Pipeline Gotchas

**AVAudioEngine cannot select non-default devices**: Calling `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` on AVAudioEngine's inputNode AUHAL is silently ignored. The engine always creates a `CADefaultDeviceAggregate` locked to the system default device's format. This is why the standalone AUHAL path exists for non-default devices.

**System default device**: Calling `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` on the already-active system default device corrupts AVAudioEngine's internal state — the tap silently receives no buffers. Always skip this call when the target device matches the system default.

**AVAudioSinkNode required**: `installTap` alone on `inputNode` does not fire callbacks — the input node must be connected through the audio graph. An `AVAudioSinkNode` (no-op consumer) is attached and connected via a `AVAudioMixerNode` to `inputNode` to keep the graph active without claiming the output device (which TeamTalk SDK uses).

**Multi-channel USB devices**: Multi-stream USB interfaces (e.g. Komplete Audio 6 MK2) only expose the first stream's channels by default via `inputNode.outputFormat(forBus: 0)`. The AUHAL audio unit must be configured to aggregate all streams by setting `kAudioUnitProperty_StreamFormat` on output scope element 1 with the full channel count from `InputAudioDeviceResolver`.

**Sample rate mismatch**: The hardware sample rate (from `inputNode.outputFormat` or AUHAL's `kAudioUnitScope_Input` element 1) may differ from `InputAudioDeviceInfo.nominalSampleRate` (from `kAudioDevicePropertyNominalSampleRate`). The capture engine overrides `targetFormat.sampleRate` to match the actual hardware rate. Any downstream consumer (e.g. `AdvancedMicrophonePreviewController`) must read the effective rate from the capture engine after start, not from the nominal device info.

**Apple AEC/VPIO removed**: The `AppleVoiceChatAudioEngine` (Voice Processing IO for echo cancellation) was removed entirely — it didn't work well. All microphone capture now goes through `AdvancedMicrophoneAudioEngine` exclusively.

### Audio Latency Profile (measured)

The app-side audio pipeline adds **< 0.3 ms** from gain application to `TT_InsertAudioBlock`. The dominant capture latency is the tap/accumulation buffer size (~40 ms), capped by `min(txIntervalMSec, 40)`. The AUHAL path accumulates ~40ms of frames before processing. The SDK internal queue adds 0-80 ms before encoding. Any perceived latency beyond that comes from the Opus codec, network, or server-side processing — not from the app pipeline.

### User Volume Curve

User volume uses a **geometric (perceptually-uniform / dB-linear) curve** anchored on the SDK volume constants:
- 0% → silence (`SOUND_VOLUME_MIN`), 50% → `SOUND_VOLUME_DEFAULT` (unity), 100% → `SOUND_VOLUME_MAX`
- `volume = DEFAULT * (MAX/DEFAULT)^((pct-50)/50)`; inverse uses `log`. Each percent is a constant ~0.6 dB step, so the slider sounds even across its range.
- Was piecewise-linear (changed in PR #22, 1.7.0-beta.7): a plain linear-gain map made the top half brutal — at `SOUND_VOLUME_MAX`=32000 (32×), 50→51% jumped ~+4 dB while 99→100% barely moved.
- Percent and volume are both clamped to range, then rounded
- Slider range: 0–100 (matching Qt client)
- Functions: `TeamTalkConnectionController.userVolumeFromPercent()` / `percentFromUserVolume()` (in `+Audio`, `nonisolated static`)
- User volumes are persisted per-username in `UserVolumeStore` (UserDefaults) and restored on user join.

### CPU Performance

The audio pipeline in Release mode uses **< 0.2% CPU**. Debug builds are ~75x slower due to Swift runtime overhead (bounds checks, generic metadata resolution) — always profile with Release builds.

**Auto-away check** (`currentIdleSecondsLocked()`) queries IOKit via `IORegistryEntryCreateCFProperties` which involves expensive mach_msg round-trips. It is throttled to once every 5 seconds (not on every 100ms polling tick).

**Profiling**: Use `sample <PID> <seconds> -file /tmp/output.txt` to capture CPU profiles.

### Auto-Away and VoiceOver

Auto-away activates when `HIDIdleTime >= threshold` (configurable, default 3 minutes). Deactivation only triggers when `HIDIdleTime < 10 seconds`, meaning real physical input (keyboard/mouse/trackpad) just happened. This fixed threshold prevents false deactivation caused by VoiceOver announcements or braille display updates briefly resetting `HIDIdleTime` when auto-away activates.

### Threading Model

- `TeamTalkConnectionController` uses a serial `DispatchQueue` for all SDK operations. Public methods dispatch to this queue internally.
- `@MainActor` is used for delegate callbacks and UI-facing properties.
- **AVAudioEngine tap callback** runs on AVAudioEngine's internal thread — no heap allocations, no locks beyond the state snapshot pattern.
- **AUHAL input callback** runs on CoreAudio's real-time IO thread — all buffers pre-allocated, single `stateLock` acquisition for state snapshot, accumulation into pre-allocated buffer, zero heap allocation.
- Audio chunks are dispatched from the capture thread to the TeamTalk queue via a single `queue.async` hop. This is the only thread transition in the capture path.
- `EchoCanceller.feedReference()` runs on the TeamTalk queue; `processCapture()` runs on the capture thread. They use separate buffers (renderAccumulator vs captureAccumulator). WebRTC APM handles its own internal synchronization.

### AudioLogger

`AudioLogger` writes diagnostic logs to `~/Library/Logs/TTAccessible/audio.log` (sandboxed path). Thread-safe: captures `Date()` on calling thread, formats timestamp and writes to file on a serial dispatch queue. No `DateFormatter` used (not thread-safe) — uses `Calendar.dateComponents` instead. Log file is cleared on each app launch. Useful for debugging audio device issues, hot-plug, and engine start/stop.

### Extension File Convention

Large classes are split into `ClassName+Responsibility.swift` files. Swift does not allow `private` access across files — shared members use `internal` (no access modifier keyword).

### Localization

```swift
L10n.text("key")              // NSLocalizedString wrapper
L10n.format("key", arg1, ...) // String(format:) wrapper
```

String files: `App/ttaccessible/en.lproj/Localizable.strings`, `App/ttaccessible/fr.lproj/Localizable.strings`.

### Help Book (user guide)

The Help menu (`⌘?`) opens an **Apple Help Book** shown in the system help viewer — `Tips.app` on
macOS 26, bundle id `com.apple.helpviewer`; never hard-code a path to the old `Help Viewer.app`.

- **Sources**: Markdown in `Help/Source/{en,fr}/`, one file per topic, with a YAML front matter
  (`title`, `description`, `keywords`, `anchor`). Both languages must expose the **same file names**
  — the script fails otherwise, because the cross-language links and `HelpAnchor` depend on it.
  French is written natively in **vouvoiement**, never translated from the English page.
- **Generated bundle**: `Help/ttaccessible.help` is **committed**, so building the app never requires
  pandoc. Regenerate with `./scripts/build-help-book.sh <version> <build>` after editing the sources.
  The script renders with pandoc, indexes each `.lproj` with `hiutil -I corespotlight -Caf … -a`, and
  then checks every internal link and every `HelpAnchor` case against the index.
- **Xcode**: the bundle is referenced explicitly in the pbxproj as a folder reference
  (`explicitFileType = folder`, never `wrapper.cfbundle`) inside the *Recovered References* group, and
  copied by the app target's `Resources` phase — same pattern as `Vendor/`. It sits outside the
  file-system synchronized group so its `.lproj` structure is not flattened. **Never add a
  `_CodeSignature` inside the `.help`**: `build.sh` seals it as an ordinary resource.
- **Code**: `Services/HelpBook.swift` (`HelpAnchor`, `HelpBook.open`, `openForKeyWindow`) plus
  `AppKit/HelpAnchors.swift`, which maps each window onto its topic. `ttaccessibleApp.swift` uses
  `CommandGroup(replacing: .help)` so the item title follows the app's language preference rather
  than the system language.
- **Caveat**: the help viewer picks its `.lproj` from the **system** language, which no public API can
  override — a user running the app in French on an English system gets the English guide. Each home
  page therefore carries a link to the other language.
- **helpd cache**: keyed on the help bundle's `CFBundleShortVersionString`, and there are **two**
  caches — `~/Library/Caches/com.apple.helpd/Generated/<id>*<version>` and a full private COPY of
  the book under `~/Library/Group Containers/group.com.apple.helpviewer.content/Library/Caches/`.
  Same version + changed content ⇒ the viewer serves the old pages. Bump the version on every
  content change, use `--dev` while writing, and purge with **`sudo hiutil -P`** — deleting those
  directories by hand leaves helpd in a state where every topic answers *"The selected content is
  currently unavailable"* until `hiutil -P` is run.

### App Sandbox

The app is sandboxed. File I/O goes to `~/Library/Containers/com.math65.ttaccessible/`.

### Feedback & Announcements (app backend)

The app talks to Mathieu's shared Go backend (`https://mathieumartin.ovh`, repo `~/dev/app-backend`, contract in its `docs/API.md`):

- **`AppBackendClient`** (`Services/`) — URLSession client for `POST /api/feedback/report` (multipart: JSON report + optional `audio.log`), `/api/feedback/contact` (JSON), `/api/announce/check` + `/ack`. Report sections use the backend's ordered-ARRAY form (`{title, type: "kv", rows: [{label, value}]}`) so plain `JSONSerialization` preserves order. Branch on `error_code`, never on the (French) server `message`.
- **`FeedbackWindowController`** (`AppKit/`) — "Contact the Developer" window (Help menu), SwiftUI form hosted in NSWindow. Type "Report a problem" → report endpoint with diagnostic sections (versions, macOS, audio devices/AEC/preset) + optional `audio.log`; other types → contact endpoint. Diagnostic section titles/values are intentionally French (they land in the report email, not the UI).
- **`AnnouncementService`** (`Services/`) — at launch (+2 s), checks for an active announcement (`lang` fr/en from the app UI language), shows it in an NSAlert, then acks. `once` mode is enforced client-side via `appBackendSeenAnnouncementIDs` in UserDefaults. Stable `appBackendInstallID` UUID in UserDefaults (server only stores a hash).
- **Bearer secret** — loaded from `App/ttaccessible/AppBackendSecret.plist` (key `BearerSecret`), which is **git-ignored** (public repo) and auto-bundled into Resources by the synchronized group. Without the file, `AppBackendClient.isConfigured` is false and the Help-menu item is hidden; builds still succeed. Server side: app id `ttaccessible` must be registered in app-backend `config/apps.json` with the matching secret in `/etc/app-backend/env`.
- Rate limit: 5 requests/hour per service per IP — mind it when testing sends.

### WebRTC Audio Processing (Vendor)

`Vendor/WebRTC/` contains the WebRTC AEC3 static library and headers:
- **Source**: `webrtc-audio-processing` v2.0 from [freedesktop.org](https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing), based on WebRTC M131.
- **Build**: Meson static build for macOS arm64. Abseil-cpp 20240722 bundled as subproject. Combined into one `.a` via `libtool`.
- **Rebuild**: `brew install meson ninja`, clone v2.0, `meson setup builddir --default-library=static`, `meson compile -C builddir`, combine all `.a` with `libtool -static`, `strip -S`.
- **Headers**: vendored in `Vendor/WebRTC/include/` (WebRTC API + abseil 20240722). Do NOT use homebrew abseil headers (version mismatch).
- **Integration**: `WebRTCEchoCanceller.h` (C API, in `Vendor/WebRTC/`) + `WebRTCEchoCanceller.mm` (ObjC++ impl in `App/ttaccessible/Services/`) + bridging header. Linked with `-lc++`.

**Note**: The TeamTalk SDK also bundles WebRTC audio processing internally, but it only works with `TT_InitSoundDuplexDevices()` (real sound devices in duplex mode). It does NOT work with `TT_InsertAudioBlock` / virtual device. That's why we run our own AEC3 instance.

### Original TeamTalk Reference

The original Qt/C++ TeamTalk client is at `../ttoriginal/Client/qtTeamTalk/`. Key reference files: `mainwindow.cpp` (features), `utilsound.cpp` (audio init, volume curve). The original uses `TT_InitSoundInputDevice` + `TT_EnableVoiceTransmission` (direct SDK path) — we cannot use this due to audio saturation.

### Removed Features

The following features were explicitly removed by the user and should NOT be re-added:

- **Custom DSP processing** — gate, expander, limiter were all removed from the audio engine and from `AdvancedInputAudioPreferences`. The model now only contains `preset` and `echoCancellationEnabled`. Old saved preferences decode without crashing (unknown keys are silently ignored by the Codable decoder).
- **Separate Advanced Microphone Settings window** — `AdvancedMicrophoneSettingsView` and `AdvancedMicrophoneSettingsWindowController` were deleted. All microphone controls (AEC toggle, channel preset picker, audio preview) are now inline in `PreferencesAudioView`.
- **"Advanced processing enabled" toggle** (`isEnabled`) — removed from the model and all UI. Microphone processing (channel preset, AEC) is always active.
- **Audio Unit plugin chain** — was briefly implemented then removed. No AU instantiation, no effect chain.
- **App audio capture** — ScreenCaptureKit / CATapDescription capture, ring buffer mixer, and all related UI were removed entirely (7 files deleted).
- **Apple Voice Processing (VPIO)** — removed, didn't work well. Replaced by WebRTC AEC3.
- **Custom NLMS echo canceller** — homemade NLMS adaptive filter was replaced by WebRTC AEC3 (much better quality, no CPU issues in Debug builds).
- **Audio diagnostics logging** — `AudioDiagnosticsLogger` and all `logAudio`/`logDiagnostics` calls removed. Was causing unnecessary CPU usage (per-chunk stats computation). Replaced by `AudioLogger` for file-based diagnostics (lightweight, no per-chunk computation).
- **Performance loggers** — `AppPerformanceLogger` and `PreferencesPerformanceLogger` removed. They used `NSLog` on hot paths (10x/sec in the polling loop), costing more CPU than what they measured.

### Recording

Two recording modes, both managed by the SDK:
- **Muxed** (`TT_StartRecordingMuxedAudioFile`) — all voices in a single file (WAV or OGG)
- **Per-user** (`TT_SetUserMediaStorageDir`) — separate file per user, including local user (`TT_LOCAL_USERID = 0`)
- Mode is a bitmask in preferences: 1=muxed, 2=separate, 3=both
- Recording folder persisted via **security-scoped bookmarks** for sandbox access. Keep `startAccessingSecurityScopedResource()` active for the entire recording duration — do NOT release immediately after start.
- Channel change during muxed recording: stop current file, start new one automatically.
- New users logging in during separate recording get `TT_SetUserMediaStorageDir` called automatically.
- `CLIENTEVENT_USER_RECORD_MEDIAFILE` handled for error/abort detection.
- **Auto-restart on channel join** — `autoRestartRecording` preference (off by default). When enabled, if recording was active (`lastRecordingWasActive`), it auto-restarts when joining a new channel, reconnecting, or relaunching the app. Toggle in Preferences > Recording.

### @Published willSet Gotcha

`@Published` emits via `willSet` — the property still holds the OLD value when subscribers receive the notification. Subscribers must either use the **closure parameter** (the new value) or insert `.receive(on: DispatchQueue.main)` to defer reading until after the assignment completes. Re-reading the source property directly inside the sink returns stale data.

Concrete cases hit:
- **`RecordingPreferencesStore.init()`** — Picker/Toggle didn't update in real-time until the subscriber switched to the closure parameter.
- **`SavedServersWindowController.observeMenuState()`** — toolbar was always one state behind (showed connected-mode items right after disconnect, and vice versa) because the sink re-read `menuState.mode`. Fixed with `.receive(on: DispatchQueue.main)`.

### AppKit / NSToolbar Gotchas

The main window has a context-aware `NSToolbar` on `SavedServersWindowController`. Pitfalls encountered while building it:

- **`titleVisibility = .hidden` + `titlebarAppearsTransparent = true` kill VoiceOver navigation** of toolbar items. The "minimal unified" look removes the standard titlebar AX container, so VO+arrows skip the entire toolbar. Keep the standard window chrome (`.titled` style mask, default title visibility) on accessibility-critical windows.
- **`NSToolbarItem` needs `isBordered = true` on macOS 11+** to render as a clickable button. Without it, items show as flat images that aren't actionable and aren't AX-focusable.
- **`NSApp.delegate as? AppDelegate` returns nil in SwiftUI apps.** `@NSApplicationDelegateAdaptor` wraps the delegate behind the `NSApplicationDelegate` protocol; the concrete-class cast fails. AppKit code that needs the AppDelegate should fall back to scanning `NSApp.windows` for a `window.delegate` of the expected type (see `SavedServersWindowController.appDelegate`).
- **`NSLog` arguments are redacted to `<private>` in unified logging.** When debugging, either run the binary directly to read stderr (`~/Library/Developer/Xcode/DerivedData/.../ttaccessible.app/Contents/MacOS/ttaccessible 2>&1 | grep TAG`) or pass `--info` to `log show`.
- **Dynamic toolbar contents**: keep all possible item identifiers in `toolbarAllowedItemIdentifiers`, return a mode-specific subset from `toolbarDefaultItemIdentifiers`, and call `toolbar.removeItem` + `toolbar.insertItem(withItemIdentifier:at:)` from the mode-change subscriber to rebuild on the fly. Disable `allowsUserCustomization` and `autosavesConfiguration` when the contents are derived from app state — saved configurations would conflict with the runtime rebuild.

### Sound Packs

Three sound packs bundled: **Default** (root of `Sounds/`), **Majorly-G**, **Old** (in subfolders with prefixed filenames to avoid Xcode resource flattening conflicts). `SoundPlayer` loads from selected pack with fallback to Default for missing sounds. Per-event enable/disable via `disabledSoundEvents: Set<NotificationSound>` in preferences.

### User Actions (Keyboard Shortcuts)

| Shortcut | Action | SDK Call |
|----------|--------|---------|
| Cmd+Shift+M | Mute/unmute selected user | `TT_SetUserMute` + `TT_PumpMessage` |
| Cmd+M | Mute/unmute master volume | `TT_SetSoundOutputMute` |
| Cmd+U | User volume + stereo balance | `TT_SetUserVolume` + `TT_SetUserStereo` |
| Cmd+I | User info | Shows user info window |
| Cmd+K | Kick from channel | `TT_DoKickUser(channelID)` |
| Cmd+Shift+K | Kick from server (admin) | `TT_DoKickUser(0)` |
| Cmd+Option+X | Move user to channel | `TT_DoMoveUser` |
| Cmd+R | Start/stop recording | `TT_StartRecordingMuxedAudioFile` / `TT_SetUserMediaStorageDir` |
| Ctrl+Cmd+O | Channel operator toggle | `TT_DoChannelOp` / `TT_DoChannelOpEx` |
| Cmd+Shift+H | Hear myself (loopback) | `TT_DoSubscribe(SUBSCRIBE_VOICE, myUserID)` |

**Skip kick confirmation**: `skipKickConfirmation` preference (off by default, Preferences > Connection). When enabled, Cmd+K and Cmd+Shift+K execute immediately without a confirmation dialog. Kick & Ban always shows confirmation regardless.

**Mute state tracking**: The outline view's `item(atRow:)` returns stale `ServerTreeNode` values after `reloadData(forRowIndexes:)` (audio runtime updates don't replace items). User mute state is tracked via `localMuteState: [Int32: Bool]` dictionary on `ConnectedServerViewController`, cleared on new session. `TT_PumpMessage(CLIENTEVENT_USER_STATECHANGE)` must be called after `TT_SetUserMute` (same pattern as Qt client).

**Volume dialog**: Real-time via `VolumeSliderHandler` (NSObject target/action on slider). Uses the geometric volume curve (see User Volume Curve section). `setUserVoiceVolumeImmediate` applies to SDK without persisting to `UserVolumeStore`. Cancel reverts to original volume and stereo state.

### Preferences Organization

6 tabs: **General** (identity, auto-away, relative timestamps, import toggle), **Connection** (auto-join, reconnect, skip kick confirmation, subscriptions, intercepts), **Audio** (devices, AEC, preset, preview), **Sounds** (global toggle, pack selector, 26 per-event toggles), **Announcements** (background modes, TTS config, per-event announcement toggles, global mode override), **Recording** (folder, mode, format, auto-restart).

All section headings use `.accessibilityAddTraits(.isHeader)` for VoiceOver heading navigation.

### Per-Event Announcement Customization

Event announcements (foreground VoiceOver + background TTS/notifications) can be individually toggled per event type. Stored as `disabledSessionHistoryKinds: Set<SessionHistoryEntry.Kind>` in `VoiceOverAnnouncementPreferences` (empty set = all enabled). Events are grouped into 7 sections in the UI: Connection, Own Channel, User Presence, Moderation, Status, Subscriptions, Files. Message types (private, channel, broadcast) have separate dedicated toggles. Codable migration handles the legacy `sessionHistoryEnabled: Bool` key.

**Global announcement mode override** (1.3.2+): `useGlobalAnnouncementMode` + `globalAnnouncementMode` in `AppPreferences`. When the global toggle is on (default), a single picker (`BackgroundMessageAnnouncementMode`) drives background behavior for ALL message/event categories — the 4 per-event mode pickers (private/channel/broadcast/event) are hidden in the UI but their stored values are preserved for when the user turns the global toggle off.

### Channel Audio Codec Configuration

Channel create/edit dialog exposes Opus codec settings: audio channels (mono/stereo), sample rate, bitrate (kbps), and application mode (VoIP/Music). Stored as `OpusCodecSettings` in `ChannelProperties`. On create, defaults from parent channel or `OpusCodecSettings.defaultSettings`. On edit, non-exposed fields (complexity, FEC, DTX, VBR, frame size) are preserved from the existing channel via `TT_GetChannel`. Bitrate is stored in bps in the SDK, displayed in kbps in the UI.

### Clickable Links in Chat

Chat messages (channel and private) use `NSTextView` with `NSDataDetector` for automatic URL detection. Links are rendered with `.link` attributes and open in the default browser on click. `LinkTextView` subclass overrides `hitTest` and `mouseDown` to only capture clicks on links — plain text clicks pass through to the table view for row selection.

### User Account Password Visibility

Admin user accounts list shows a Password column. The SDK returns plaintext passwords via `TT_DoListUserAccounts()` — the app now reads `szPassword` instead of setting it to empty. The edit form uses `NSTextField` (not `NSSecureTextField`) matching the Qt client behavior.

### Missing Features (vs original Qt client)

- **Push-to-Talk** — configurable hotkey for PTT mode (not just toggle)
- **VOX level** — configurable voice activation threshold slider
- **Mic gain hotkeys** — increase/decrease gain via keyboard shortcuts
- **Webcam capture / desktop sharing** — not implemented (low priority for accessibility). Media file streaming IS supported via `+MediaStreaming` / `+Video` (`MediaStreamingPlayerViewController`, `VideoFrameView`, `CollapsibleVideoPanelView`).
- **Custom sound packs** — loading user-provided sound packs from disk (only 3 built-in packs currently)
