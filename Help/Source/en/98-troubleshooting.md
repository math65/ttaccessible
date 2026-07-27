---
title: Troubleshooting
description: What to check when there is no sound, when the microphone stays silent, when there is echo, and how to reach the developer.
keywords: problem, no sound, microphone, echo, permission, keychain, log, support, bug report
anchor: troubleshooting
---

## I cannot hear anything

Work down this list; **F9** answers the first question for you by speaking the current audio status.

1. Is the master volume muted? **Command-M** toggles it.
2. Is the **Output volume** slider of the main window turned down?
3. In [Preferences → Audio](preferences.html#prefs-audio), is **Output device** set to **No output
   device**, or to a device you are no longer using? **Refresh Devices** rebuilds the list.
4. Is that one person muted for you? Their row says *muted*, and **Shift-Command-M** brings them
   back. Check their level in [the channel mixer](mixer.html) too.
5. Are you still subscribed to their **Voice**? See [People you hear](users.html).

## Nobody hears me

1. You must be **in a channel**. Outside one, the app answers *You must join a channel before
   enabling the microphone.*
2. Is the microphone on? **Shift-Command-A**, or the toolbar button.
3. Are you in **push-to-talk** mode without a key recorded? The Audio pane warns about it, and until
   a key is set the microphone behaves as in always-on mode.
4. Did macOS refuse access? The app reports *Microphone access was denied by macOS.* Grant it in
   System Settings → Privacy & Security → Microphone.
5. Is the right **Input device** selected, and the right **Input channels** preset? On an audio
   interface, the microphone is rarely on input 1.
6. Has an operator blocked you? The app announces *Transmission blocked by the channel operator.*

**Shift-Command-H** (*Hear myself*) settles the question: if you can hear yourself through the
channel, you are on air.

## Everyone hears themselves come back

That is echo: your speakers are being picked up by your microphone. Either use headphones, or set
**Microphone processing** to **Echo cancellation + noise reduction** in
[Preferences → Audio](preferences.html#prefs-audio). On macOS 14.2 and later this also cancels
VoiceOver and system sounds.

## The sound broke when I plugged something in

The app detects device changes and restarts its audio engine on its own. If something is still
wrong, use **Refresh Devices**. Should the microphone have stopped, the app says so —
*Microphone stopped after an audio device change. Turn it on again.*

## Recording refuses to start

The channel was probably created with **No audio recording**; the app then announces *Recording is
not allowed in this channel.* Only an account with the right to record voice can override it. See
[Recording](recording.html).

## Streaming an application does not work

- Streaming an application's or VoiceOver's audio requires **macOS 13 or later**, and browsing apps
  that are not running requires **macOS 14.2 or later**.
- If the app answers *The selected source has no audio to capture right now*, make sure the
  application is really running and playing something.

See [Streaming media](streaming.html).

## The server refuses my password

- The **Login Failed** alert offers **Edit Credentials…** so you can correct the username or the
  password.
- If the server uses BearWare web login, check that your account is signed in under
  [Preferences → BearWare](preferences.html#prefs-bearware).
- If macOS refuses access to the stored password, the app explains it: open Keychain Access, delete
  the matching **ttaccessible** entry, then try again.

## The connection keeps dropping

**Adaptive jitter buffer**, in [Preferences → Connection](preferences.html#prefs-connection),
improves audio on unstable connections. Automatic reconnection and rejoining the last channel are
both enabled by default in the same pane.

## Reporting a problem

**Help → Contact the Developer…** opens a form where you choose a type — **Report a problem**,
**Suggestion**, **Question** or **Other** — enter your email address and your message. The app
version, the macOS version and your audio settings are attached to help with troubleshooting.

The **Attach the audio diagnostic log** checkbox adds the technical audio log, which is what makes a
sound problem diagnosable. Reproduce the problem first, then send the message: the log is cleared at
every launch.

That log lives in your home folder, under
`Library/Containers/com.math65.ttaccessible/Data/Library/Logs/TTAccessible/audio.log`.

**Help → Report an Issue…** opens the project's issue tracker instead, which is the better place for
anything public.
