---
title: Talking
description: Turn the microphone on, use push-to-talk, adjust the volumes, and hear yourself.
keywords: microphone, push-to-talk, PTT, mute, master volume, hear myself, audio status, gain
anchor: talking
---

## Turning the microphone on

**Shift-Command-A** toggles the microphone. The app confirms with *Microphone enabled.* or
*Microphone muted.*, and the toolbar button reports its state.

You must be in a channel first: outside one, the app answers *You must join a channel before
enabling the microphone.*

## Microphone modes

[Preferences → Audio](preferences.html#prefs-audio) offers three ways to work, under **Microphone
mode**:

- **Always transmit** — the microphone stays open once you turn it on. This is the default.
- **Push-to-talk (hold a key to transmit)** — you transmit only while a key is held.
- **Both (mute-gated with push-to-talk)** — Shift-Command-A opens a permanent gate, and holding the
  push-to-talk key transmits regardless. Releasing the key goes silent again until you press
  Shift-Command-A or hold the key once more.

For push-to-talk you must record a key: activate **Push-to-talk key**, then press the key to hold.
Any key works, including a single one; a modifier combination on its own — Command-Control, for
instance — works as well. Press Delete to clear it. Until a key is set, the app warns that
push-to-talk is inactive and the microphone keeps transmitting as in always-on mode.

Two related options:

- **Play a sound when transmission starts and stops** — on by default.
- **Push-to-talk works when another app is in front** — on by default. There is a matching option
  for the microphone toggle, off by default. Both rely on the Input Monitoring permission, which
  macOS asks for the first time. Because the app is sandboxed, the key is detected but still reaches
  the app you are working in, so prefer a combination of modifiers on their own or a function key
  from F13 to F19 — neither types anything into another app.

## Volumes

Three sliders sit in the main window, each with a *Reset to 50%* VoiceOver action:

- **Input volume** — how loud your microphone is sent.
- **Output volume** — how loud you hear everyone.
- **Sound effects volume** — how loud the notification sounds are.

**Command-M** mutes and unmutes the master volume, announcing *Master volume muted* or *Master
volume unmuted*.

Individual people can be adjusted separately — see [People you hear](users.html) and
[The channel mixer](mixer.html).

## Hearing yourself

**Shift-Command-H** turns *Hear myself* on and off. Your own voice is then played back to you
through the channel, which is the quickest way to check that your microphone, gain and processing
are set correctly. The app announces *Hear myself enabled* or *Hear myself disabled*.

For a check before connecting, use the **Audio preview** button in
[Preferences → Audio](preferences.html#prefs-audio).

## Knowing where you stand

**F9** speaks the audio status: whether the output is active, whether the microphone is ready or
transmitting, and whether recording is running. It is the fastest way to answer *am I actually on
air?* without leaving what you are doing.

If the app reports *Transmission blocked by the channel operator*, an operator has taken your right
to speak in that channel.
