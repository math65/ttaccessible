---
title: Change tt-Accessible settings
description: Every setting of tt-Accessible, pane by pane, with its default value.
keywords: preferences, settings, general, connection, BearWare, audio, sounds, announcements, recording
anchor: preferences
---

To change your settings, choose tt-Accessible > Preferences, or press Command-comma, then click one
of the seven panes in the sidebar. Press Escape to close the window.

<a id="prefs-general"></a>

## General settings

| Setting | Default |
|---|---|
| **Default nickname** — used when a saved server has no nickname of its own | your macOS account name |
| **Default status message** | empty |
| **Gender** | Neutral |
| **Away timeout**, in minutes — 0 turns automatic away off | 3 |
| **Away message** | empty |
| **Use relative timestamps**, such as "2 min ago" | off |
| **Automatically detect the TeamTalk file format during import** | on |
| **Language** — System Default, English or French | System Default |

Automatic away sets your status to Away once you stop using the keyboard or the mouse for the number
of minutes you choose, and clears it as soon as you really use them again. Announcements from
VoiceOver or a braille display don't count as activity.

The Updates section holds **Check for updates automatically**, which is on, and **Include beta
versions**, which is off.

<a id="prefs-connection"></a>

## Connection settings

| Setting | Default |
|---|---|
| **Automatically join the main channel on connect** | on |
| **Automatically reconnect on connection loss** | on |
| **Automatically rejoin the last channel after reconnecting** | on |
| **Connect to the last used server on launch** | off |
| **Always connect with the microphone off** | off |
| **Skip confirmation when kicking users** | off |
| **Adaptive jitter buffer**, which improves audio on unstable connections | off |
| **Sort channels by** — Name, or User count | Name |
| **Show people as** — Nickname and username, Nickname only, or Username only | Nickname and username |

**Default subscriptions** decides what everyone may send you as soon as you connect: private
messages, channel messages, broadcast messages, voice, desktop sessions and media file streams. All
six are on.

**Default intercepts** — private messages, channel messages, voice, desktop sessions and media file
streams — are all off and need the matching rights on the server. Changing either list applies
immediately to the session you're in.

<a id="prefs-bearware"></a>

## BearWare settings

A free BearWare account (bearware.dk) lets you log in to servers that support web login. Enter your
**BearWare username** and **BearWare password**, then click **Sign in**. See
[Add a server and connect to it](servers.html).

<a id="prefs-audio"></a>

## Audio settings

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

See [Set up your audio devices](audio-setup.html) and [Talk in a channel](talking.html).

<a id="prefs-sounds"></a>

## Sounds settings

**Enable sound notifications**, which is on, turns every sound on or off, and **Sound pack** chooses
which set is used. Below, the twenty-six sound events can each be turned off on their own. See
[Choose sounds and announcements](sounds-announcements.html).

<a id="prefs-announcements"></a>

## Announcements settings

**Background message handling** decides what happens when something arrives while tt-Accessible
isn't the frontmost app. **Use the same mode for all event types**, which is on, applies one mode to
everything; turn it off to set private messages, channel messages, broadcast messages and TeamTalk
history separately. The three modes are **System notification**, which is the default, **macOS text
to speech**, and **VoiceOver via AppleScript**.

**Event announcements** covers what VoiceOver says while the app is in front: channel, private and
broadcast messages, all on, plus **Announce system history** — twenty events you can enable or
disable one by one.

<a id="prefs-recording"></a>

## Recording settings

| Setting | Default |
|---|---|
| **Recording folder** | none |
| **Recording mode for Cmd+Shift+R** — Separate files, or Both | Both |
| **Audio format** — WAV or OGG (Opus) | WAV |
| **Automatically restart recording when joining a channel** | off |

Command-R always records a single mixed file, whatever this mode says. See
[Record a conversation](recording.html).
