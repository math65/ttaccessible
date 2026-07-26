---
name: audio-log
description: Inspect the ttaccessible audio diagnostics log at ~/Library/Logs/TTAccessible/audio.log. Use this skill whenever the user is investigating an audio issue — mic not working, no input level, echo or feedback, crackling/saturation, AEC not cancelling, device hot-plug bugs, mic preview freeze, output device switch problems, AVAudioEngine or AUHAL failures — or asks to "check the audio log", "debug the mic", "see what AEC is doing". The log is wiped on each app launch, so always reproduce the issue first, then read. Includes ready-made grep patterns (`AEC diag:`, device events, engine lifecycle, errors).
---

# Inspect the audio log

`AudioLogger` writes diagnostic events to `~/Library/Logs/TTAccessible/audio.log` (sandboxed path). The file is cleared on each app launch — so reproduce the issue, then read.

## Path

```
~/Library/Logs/TTAccessible/audio.log
```

## Useful queries

```bash
# Last 200 lines
tail -n 200 ~/Library/Logs/TTAccessible/audio.log

# Live tail while reproducing
tail -f ~/Library/Logs/TTAccessible/audio.log

# AEC convergence diagnostics (logged every 5 s when AEC is on)
grep "AEC diag:" ~/Library/Logs/TTAccessible/audio.log

# Device hot-plug events
grep -iE "device|restart sound|aggregate" ~/Library/Logs/TTAccessible/audio.log

# Engine lifecycle
grep -iE "engine (start|stop)|AUHAL|AVAudioEngine" ~/Library/Logs/TTAccessible/audio.log

# Errors / warnings
grep -iE "error|warn|failed|drop" ~/Library/Logs/TTAccessible/audio.log
```

## Reading AEC diag entries

Each `AEC diag:` line reports the configured rate/channels, current reference/capture rates, and cumulative frame counts. Mismatched reference vs capture rates are the most common cause of poor cancellation — confirm both match the hardware capture rate (e.g. 44100 Hz for most USB mics), and that the reference signal source is the speaker tap (macOS 14.2+) or the `TT_MUXED_USERID` fallback.

## Reproducing a clean log

The log is wiped on launch. To capture a focused trace:
1. Quit the app.
2. Relaunch.
3. Reproduce the issue immediately.
4. Read the log before any unrelated session noise accumulates.
