---
title: Talk in a channel
description: Turn your microphone on, use push-to-talk, adjust the volumes, and check that you're on air.
keywords: microphone, push-to-talk, PTT, mute, master volume, hear myself, audio status, gain
anchor: talking
---

You can talk as soon as you join a channel. tt-Accessible can keep your microphone open, or send
your voice only while you hold a key.

## Turn the microphone on or off

Press Shift-Command-A. tt-Accessible confirms with *Microphone enabled* or *Microphone muted*, and
the toolbar button shows its state.

You must be in a channel first. Outside one, tt-Accessible answers *You must join a channel before
enabling the microphone.*

## Choose how your microphone transmits

1. Open Preferences, then click Audio in the sidebar.
2. Click the **Microphone mode** pop-up menu, then choose one of the following:
   - **Always transmit** — the microphone stays open once you turn it on.
   - **Push-to-talk** — you transmit only while you hold a key.
   - **Both** — Shift-Command-A opens a permanent gate, and holding the push-to-talk key transmits
     whatever the gate is set to.
3. For push-to-talk, click **Push-to-talk key**, then press the key you want to hold. Any key works,
   including a single one or a combination of modifier keys on their own, such as Command-Control.
   Press Delete to clear it.

Until you record a key, push-to-talk stays inactive and the microphone keeps transmitting as in
always-on mode. tt-Accessible warns you in the same pane.

Two related options sit just below:

- **Play a sound when transmission starts and stops**, which is on.
- **Push-to-talk works when another app is in front**, which is on. A matching option exists for the
  microphone toggle, and is off.

## Use your microphone from another app

With either of those options on, the shortcut answers wherever you are — in your browser, in your
audio editor, anywhere.

macOS gives the key to tt-Accessible before the app in front sees it, so nothing is typed where
you're working. That app no longer receives the key at all: if your audio editor pauses on
Control-Space and you choose Control-Space here, it stops pausing for as long as the shortcut is
set. Choose one you don't use elsewhere — a function key from F13 to F19 is a safe bet.

Also worth knowing:

- An ordinary shortcut needs no permission.
- A combination of modifier keys on their own, such as Command-Control, is the exception. macOS asks
  for the Input Monitoring permission the first time, and the app in front still receives the keys.
- A key that types — a letter, Space, Return, an arrow — is refused. It would stop that character
  reaching any text field, including the chat here.
- While a password field is focused anywhere on your Mac, macOS suspends the shortcut. It works
  again as soon as you leave that field.

## Adjust the volumes

The main window has three sliders, each with a *Reset to 50%* VoiceOver action:

- **Input volume** — how loud your microphone is sent.
- **Output volume** — how loud you hear everyone.
- **Sound effects volume** — how loud the notification sounds are.

To mute or unmute everything at once, press Command-M.

To set the level of one person, see [Adjust what you hear from each person](users.html) and
[Balance a channel with the mixer](mixer.html).

## Check that people can hear you

- To hear your own voice through the channel, press Shift-Command-H. If you can hear yourself,
  you're on air.
- To hear a summary of the audio status, press F9.
- To test your microphone before connecting, open Preferences, click Audio, then click **Audio
  preview**.

If tt-Accessible announces *Transmission blocked by the channel operator*, an operator has taken
your right to speak in that channel.

**See also:** [Set up your audio devices](audio-setup.html) ·
[If something doesn't work](troubleshooting.html)
