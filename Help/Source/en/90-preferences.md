---
title: Preferences
description: Every setting of tt-Accessible, pane by pane, with its default value.
keywords: preferences, settings, general, connection, BearWare, audio, sounds, announcements, recording
anchor: preferences
---

**Command-comma** opens Preferences. The window has seven panes, listed in a sidebar: General,
Connection, BearWare, Audio, Sounds, Announcements and Recording. Escape closes the window, and
Command-question-mark opens the section of this guide that matches the pane you are in.

<a id="prefs-general"></a>

## General

| Setting | Default |
|---|---|
| **Default nickname** — used when a saved server has no specific nickname | your macOS account name |
| **Default status message** | empty |
| **Gender** | Neutral |
| **Away timeout**, in minutes — 0 disables automatic Away | 3 |
| **Away message** | empty |
| **Use relative timestamps (e.g. "2 min ago")** | off |
| **Automatically detect the TeamTalk file format during import** | on |
| **Language** — System Default, English or French | System Default |

Automatic away switches your status to *Away* once you stop touching the keyboard or the mouse for
the chosen number of minutes, and switches it back as soon as you really touch them again.
Announcements from VoiceOver or a braille display do not count as activity.

Changing the language requires restarting the app for it to apply everywhere.

The **Updates** section holds **Check for updates automatically** (on) and **Include beta
versions** (off). Beta versions may contain bugs.

<a id="prefs-connection"></a>

## Connection

| Setting | Default |
|---|---|
| **Automatically join the main channel on connect** | on |
| **Automatically reconnect on connection loss** | on |
| **Automatically rejoin the last channel after reconnecting** | on |
| **Connect to the last used server on launch** | off |
| **Skip confirmation when kicking users** | off |
| **Adaptive jitter buffer (improves audio on unstable connections)** | off |
| **Sort channels by** — Name, or User count (most populated first) | Name |

**Default subscriptions** decides what you receive from everyone as soon as you connect: private
messages, channel messages, broadcast messages, voice, desktop sessions and media file streams. All
six are on by default.

**Default intercepts** — private messages, channel messages, voice, desktop sessions and media file
streams — are all off, and need the matching rights on the server. Changing either list applies
immediately to the running session.

See [People you hear](users.html) for the per-person version of these switches.

<a id="prefs-bearware"></a>

## BearWare

A free BearWare account (bearware.dk) lets you log in to servers that support web login. Enter your
**BearWare username** and **BearWare password**, then **Sign in**; the pane then shows who you are
signed in as and offers **Sign out**.

Web login is then enabled per server, in that server's own settings. See [Servers](servers.html).

<a id="prefs-audio"></a>

## Audio

| Setting | Default |
|---|---|
| **Output device** — System default, a specific device, or No output device | System default |
| **Input device** | System default |
| **Microphone processing** — None, Noise reduction, or Echo cancellation + noise reduction | None |
| **Input channels** — Auto, a mono input, a stereo pair or a mono mix | Auto |
| **Microphone mode** — Always transmit, Push-to-talk, or Both | Always transmit |
| **Push-to-talk key** | not set |
| **Play a sound when transmission starts and stops** | on |
| **Push-to-talk works when another app is in front** | on |
| **Microphone toggle hotkey works when another app is in front** | off |
| **Global microphone toggle key** | Command-Shift-A |
| **Per-user volume memory** — Off, This session only, or Always | Always |

**Refresh Devices** rebuilds the device list, and **Audio preview** plays your microphone back to
you for a test. The details are in [Setting up audio](audio-setup.html) and
[Talking](talking.html).

<a id="prefs-sounds"></a>

## Sounds

**Enable sound notifications** (on) turns the whole set on or off, and **Sound pack** chooses which
one is used. Below, the twenty-six sound events can each be turned off individually; all are on by
default.

The buttons **New Pack...**, **Required Files...**, **Reveal Packs Folder** and, for your own packs,
**Delete** and the per-event **Choose...** / **Reset** let you build a pack of your own. See
[Sounds and announcements](sounds-announcements.html).

<a id="prefs-announcements"></a>

## Announcements

**Background message handling** decides what happens when a message or an event arrives while
tt-Accessible is not the frontmost app. **Use the same mode for all event types** (on) applies a
single **Mode** to everything; turn it off to set private messages, channel messages, broadcast
messages and TeamTalk history separately. The three modes are **System notification** (the default),
**macOS text to speech** and **VoiceOver via AppleScript**.

**macOS text to speech** configures that mode: **Voice**, **Speech rate**, **Volume** and a **Test
voice** button.

**Event announcements** covers what is spoken while the app *is* in front: channel messages, private
messages and broadcast messages, each on by default, plus **Announce system history** — twenty
events grouped by theme, with **Enable all** and **Disable all**.

<a id="prefs-recording"></a>

## Recording

| Setting | Default |
|---|---|
| **Recording folder** | none |
| **Recording mode for Cmd+Shift+R** — Separate files, or Both | Both |
| **Audio format** — WAV or OGG (Opus) | WAV |
| **Automatically restart recording when joining a channel** | off |

Command-R always records a single mixed file, whatever the mode above says. See
[Recording](recording.html).
