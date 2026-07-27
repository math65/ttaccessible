---
title: Setting up audio
description: Choose input and output devices, enable noise reduction or echo cancellation, and test your microphone.
keywords: audio device, input, output, echo cancellation, AEC, noise reduction, preview, channels, headphones
anchor: audio-setup
---

Everything on this page lives in [Preferences → Audio](preferences.html#prefs-audio). Changes take
effect immediately, even during a session.

## Devices

- **Output device** — **System default**, any output on your Mac, or **No output device** if you
  want to run the app silently.
- **Input device** — **System default** or a specific microphone.

**Refresh Devices** rebuilds the list after plugging or unplugging hardware. The app also notices
device changes on its own and restarts its audio engine, so headphones connected mid-session are
picked up without action from you.

## Microphone processing

**Microphone processing** offers three settings:

- **None** — your microphone is sent as it is.
- **Noise reduction** — removes background noise from your microphone.
- **Echo cancellation + noise reduction** — additionally removes the sound of your speakers from
  what you send, and always includes noise reduction.

Echo cancellation is what makes it possible to work **without headphones**: without it, everyone
hears themselves come back through your microphone. On macOS 14.2 and later the app uses the actual
mixed system output as its reference, so VoiceOver and system sounds are cancelled along with the
voices of the channel. On older systems only TeamTalk audio can be cancelled.

## Input channels

**Input channels** decides which physical inputs of the device are used:

- **Auto** — let the app choose.
- **Input _n_ mono** — a single input.
- **Inputs _n_/_n_ stereo** — a stereo pair.
- **Mono mix _n_+_n_** — two inputs summed to mono.

This matters with multi-input audio interfaces, where the microphone is rarely on input 1. If the
device changes and the chosen preset no longer fits, the app falls back to **Auto** and says so.

## Testing before you talk

**Audio preview** plays your microphone back to you, with the processing you selected, without
being connected to anything. Press it again — **Stop preview** — to end the test.

During a session, **Shift-Command-H** (*Hear myself*) does the same through the channel.

## Volume memory

**Per-user volume memory** decides what happens to the levels you set for individual people:

- **Off** — always reset to 50% on reconnect.
- **This session only** — forget on quit.
- **Always** — remember across launches. This is the default.

Adjustments are scoped per server, so a level set on one server never carries over to another.

## If the audio misbehaves

The app writes a diagnostic log you can consult or attach to a message to the developer; see
[Troubleshooting](troubleshooting.html).
