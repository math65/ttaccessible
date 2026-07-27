---
title: The main window
description: The areas of the session window, how to move between them with Command-1 to Command-5, and what the channel tree announces.
keywords: main window, layout, focus, channel tree, session history, audio bar, nickname, status
anchor: main-window
---

Once connected, the window is titled **Connected Server:** followed by the server name. It holds
everything you need in a single place.

## The five areas

| Shortcut | Area | What it holds |
|---|---|---|
| Command-1 | Main area | The tree of channels and users |
| Command-2 | Chat history | Messages sent in your channel |
| Command-3 | Message input | Where you type, with a **Send** button |
| Command-4 | Session history | Everything that happened during the session |
| Command-5 | Channel Mixer | One strip per person you can hear |

These shortcuts move the keyboard focus — and with it the VoiceOver cursor — so you can jump
straight to the part you need instead of walking through the window. They also work while the
**Private Messages** window is in front, where Command-1, Command-2 and Command-3 focus its
conversation list, its history and its input field. When no session is running, Command-1 brings
back the **TeamTalk Servers** window and selects the server list.

## The channel tree

The tree lists the server's channels and, under each one, the people in it. Arrow keys browse it;
**Return** joins the selected channel. Right-clicking — or the VoiceOver actions rotor — opens the
**Channel** menu with the actions described in [Channels](channels.html) and
[People you hear](users.html).

Each row is announced with everything that matters about it:

- A channel adds *current channel*, *password protected* or *hidden* when they apply, and reads its
  topic when it has one.
- A person adds *you*, *administrator*, *channel operator*, *talking*, *away* or *question*.

The order of channels follows *Sort channels by* in
[Preferences → Connection](preferences.html#prefs-connection): by **Name**, or by **User count (most
populated first)**.

## Session history

The session history collects the events of the session: connections, people arriving and leaving,
channel changes, kicks, subscription changes, files added or removed, automatic away, and media
streaming. Each entry can be announced out loud or kept silent — see
[Sounds and announcements](sounds-announcements.html).

Timestamps can be shown as clock times or as relative times such as *2 min ago*, depending on *Use
relative timestamps* in [Preferences → General](preferences.html#prefs-general).

**Shift-Command-S** exports the chat history to a file.

## The audio bar

Below the lists you will find:

- The microphone button — **Enable microphone** or **Mute microphone**.
- Three sliders: **Input volume**, **Output volume** and **Sound effects volume**. Each one offers
  the VoiceOver action *Reset to 50%*.

**F9** speaks the current audio status at any time — whether output is active, whether the
microphone is ready or transmitting, and whether recording is running.

## Your identity on the server

- **F5** — *Change Nickname*. Leave the field empty to fall back to your default nickname.
- **F6** — *Change Status*: a status mode (**Available**, **Away** or **Question**), a gender, and an
  optional status message.

Automatic away can also change your status for you when you stop touching the keyboard; see
[Preferences → General](preferences.html#prefs-general).

## Video

When someone streams a video file into the channel, a collapsible **Video** panel appears. It can be
shown or hidden and reports *No video* when nothing is playing.

## Reconnecting

If the connection drops, the window shows **Reconnecting…** and the app tries to bring the session
back — including rejoining the channel you were in, when the matching options are enabled in
[Preferences → Connection](preferences.html#prefs-connection).

## Leaving

**F2** disconnects. If the server was opened from a `.tt` file or a link and was never saved, the app
offers to save it first.
