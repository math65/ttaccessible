# TTAccessible — Audio Output Bypass Plan (handoff)

> Goal: stop letting the TeamTalk SDK own a **physical** CoreAudio output device.
> Render the mixed server audio ourselves through our own CoreAudio output engine,
> exactly as the app already does for the **input** (custom AUHAL capture → virtual
> device). This eliminates `TT_CloseSoundOutputDevice`, which is the root of the
> intermittent device-switch deadlock.

## Why (the proven problem)

Device switching while connected intermittently **deadlocks** and loses all audio.
Confirmed by disassembling `Vendor/TeamTalk/libTeamTalk5.dylib`:

- `TT_CloseSoundOutputDevice` → `ClientNodeBase::ReactorLock()` → `ClientNode::CloseSoundOutputDevice` → locks an **ACE_Recursive_Thread_Mutex** → `ResetAudioPlayers()`.
- Backend is **PortAudio** on CoreAudio (`PaSoundGroup`/`PaOutputStreamer` symbols).
- Under HAL overload ("HALC_ProxyIOContext: skipping cycle due to overload") the output IO thread is stuck holding the audio mutex, so the close hangs **while holding the reactor lock** → the whole SDK freezes → audio never recovers.
- A normal close already takes ~250–285 ms; occasionally it never returns.
- Not patchable: it's deep in PortAudio's CoreAudio HAL stop + ACE mutex inside a 68 MB signed universal dylib. This is a BearWare/SDK issue.

Mitigations already shipped (mute+settle before close, only-reinit-the-changed-device)
**reduce** the odds but cannot eliminate it. The bypass is the real cure.

## The approach (mirror the existing input bypass)

The app ALREADY does this pattern for input: custom `AdvancedMicrophoneAudioEngine`
(AUHAL capture) feeds PCM to the SDK via `TT_InsertAudioBlock` through
`TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL`. Do the symmetric thing for output:

1. **Point the SDK output at the virtual device** (`TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL` = 1978) so the SDK never opens a real CoreAudio output device.
2. **Pull the mixed audio** via `TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, streamTypes, 1)` and `TT_AcquireUserAudioBlock(...)`. The app ALREADY taps this for AEC (see `TeamTalkConnectionController+Audio.swift` ~line 381 and `+Connection.swift` ~line 505). Use stream types `STREAMTYPE_VOICE | STREAMTYPE_MEDIAFILE_AUDIO` so media-file playback is included (the recording feature already muxes both).
   - Per-user volume + jitter buffering are applied by the SDK **before** the mux, so we keep them for free. Master volume/mute become ours to apply on the muxed stream.
3. **Render that PCM to the selected output device** through our own CoreAudio/AVAudioEngine output engine — bind `outputNode` to the device via `kAudioOutputUnitProperty_CurrentDevice` (we already do this for preview routing; device resolution via `InputAudioDeviceResolver.resolveOutputDevice(persistentID:displayName:)`).
4. **Switching the output device = our code.** Re-bind our output engine's device. No SDK close, no deadlock. Fast and reliable.

## Things to handle / risks

- **Latency/buffering:** add a small jitter/ring buffer between the muxed-block callback and our render callback. Tune for low latency without underruns.
- **Media files & sounds:** make sure the muxed stream includes media-file audio (STREAMTYPE_MEDIAFILE_AUDIO). The app's own notification sounds already route via `NSSound.playbackDeviceIdentifier` (separate, done).
- **Master mute/volume:** now applied by us on the muxed PCM (was `TT_SetSoundOutputMute` / `TT_SetSoundOutputVolume`).
- **AEC reference:** AEC currently speaker-taps the output. With us owning the render, the AEC reference can come straight from our render buffer (cleaner than the CADefaultDeviceAggregate tap).
- **Format:** muxed block format (rate/channels) → resample to the output device rate in our engine (the input engine already has an `AudioPCMResampler`).
- **Coordinate with math65:** this is a core-architecture change to his app. It extends his own input-bypass design and removes BearWare from the audio critical path — likely welcome, but discuss before it lands in a PR.

## Current branch state

Branch `fix/audio-launch-and-device-switching` (fork `rfiorentino1/ttaccessible`), 9 commits, all build clean (Debug + Release), SDK fetched via `./scripts/download-sdk.sh`:

1. Defer launch-time device enumeration off the launch tick
2. Audio device re-selection after a failed apply (optional lastApplied, clear on failure)
3. Move device-catalog load off the main thread (the ~15 s launch hang)
4. Route mic preview to selected output at its native rate
5. Remove per-sample array bounds checks from the AUHAL RT callback (Debug crackle)
6. Seed device pickers from a persisted cache (instant list)
7. Restore fast device switching (ee7af8b regression) + mute/settle deadlock mitigation + switch-path logging
8. Only reinitialize the device that actually changed (input switch never closes output)
9. Play app notification sounds through the selected output device (NSSound)

Commits 1–6 + 9 are solid and shippable. 7–8 improve switching but the output-close
deadlock persists → that's what THIS plan fixes.

Diagnostic log lives at:
`~/Library/Containers/com.math65.ttaccessible/Data/Library/Logs/TTAccessible/audio.log`
(sandboxed; cleared each launch). The switch path is heavily instrumented.

## Note on local pbxproj

The working tree has an uncommitted `project.pbxproj` change = Rocco's
`DEVELOPMENT_TEAM` (4N3BKC95BL). Keep it LOCAL — do NOT include it in any PR
(upstream is math65's team 633EG76YX5).
