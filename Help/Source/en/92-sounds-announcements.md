---
title: Sounds and announcements
description: Choose a sound pack, build your own, and decide what the app says out loud in the foreground and in the background.
keywords: sounds, sound pack, notification, announcement, VoiceOver, text to speech, background
anchor: sounds-announcements
---

tt-Accessible tells you what happens in two ways: short sounds, and spoken announcements. Both are
configured event by event.

## Sound packs

Three packs are built in — **Default**, **Majorly-G** and **Old** — and are chosen with **Sound
pack** in [Preferences → Sounds](preferences.html#prefs-sounds). **Enable sound notifications** turns
every sound off in one move.

To build your own:

1. **Required Files...** lists every file name the app looks for and the event it is used for.
   Prepare a folder of WAV files with those names. Any file you leave out falls back to the Default
   pack.
2. **New Pack...** imports that folder. Its name becomes the name of the pack.
3. Once your pack is selected, **Edit selected pack** appears: each event shows whether it is
   **Custom** or **Default**, with **Choose...** to point it at another file and **Reset** to go
   back.
4. **Reveal Packs Folder** opens the folder where your packs are stored, and **Delete** removes the
   selected one. Deleting a custom pack also deletes it from this Mac.

The volume of these sounds follows the **Sound effects volume** slider of the main window.

## The twenty-six sound events

Each of these can be turned off on its own:

| | |
|---|---|
| User joined channel | User left channel |
| Private message received | Private message sent |
| Channel message received | Channel message sent |
| Connection lost | Broadcast message |
| User logged in | User logged out |
| File added or removed | File transfer complete |
| Question mode | Hotkey pressed |
| Voice activation on | Voice activation off |
| Mute all | Unmute all |
| Intercept started | Intercept ended |
| Transmit queue start | Transmit queue stop |
| VOX enabled | VOX disabled |
| Microphone activated | Microphone deactivated |

## Spoken announcements

[Preferences → Announcements](preferences.html#prefs-announcements) separates two situations.

### While tt-Accessible is in front

**Event announcements** covers what is spoken through VoiceOver:

- **Announce channel messages**, **Announce private messages** and **Announce broadcast
  messages** — all on by default.
- **Announce system history**, a list of twenty events you can enable or disable one by one, with
  **Enable all** and **Disable all**. They are grouped as **Connection** (connected, disconnected,
  connection lost), **Own channel** (joined, left), **User presence** (logged in and out, joined and
  left a channel), **Moderation** (kicked from the server or the channel, transmission blocked),
  **Status** (auto-away on and off), **Subscriptions** (subscription and intercept changes),
  **Files** (added, removed) and **Media streaming** (started, finished).

Turning an event off only silences the announcement — the entry still appears in the session
history.

### While another app is in front

**Background message handling** decides how you are told when tt-Accessible is not frontmost:

- **System notification** — a standard macOS notification. This is the default.
- **macOS text to speech** — the app speaks the message itself, with the **Voice**, **Speech rate**
  and **Volume** set below. **Test voice** tries the current settings.
- **VoiceOver via AppleScript** — VoiceOver announces the message.

**Use the same mode for all event types** is on by default and applies one mode to everything. Turn
it off to choose a different mode for private messages, channel messages, broadcast messages and
TeamTalk history — for example a spoken alert for private messages and a silent notification for the
rest.
