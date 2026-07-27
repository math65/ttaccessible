---
title: Choose sounds and announcements
description: Pick a sound pack or build your own, and decide what tt-Accessible says out loud in the foreground and in the background.
keywords: sounds, sound pack, notification, announcement, VoiceOver, text to speech, background
anchor: sounds-announcements
---

tt-Accessible tells you what happens in two ways: short sounds, and spoken announcements. You can
set both event by event.

## Choose a sound pack

1. Open Preferences, then click Sounds in the sidebar.
2. Click the **Sound pack** pop-up menu, then choose **Default**, **Majorly-G** or **Old**.

To turn every sound off at once, deselect **Enable sound notifications**.

The level of these sounds follows the **Sound effects volume** slider of the main window.

## Turn individual sounds off

In the Sounds pane, deselect any of the twenty-six sound events. They cover people joining and
leaving, messages sent and received, connection loss, files, transfers, question mode, hotkeys,
voice activation, muting, intercepts, the transmit queue, VOX, and your own microphone.

## Build your own sound pack

1. Open Preferences, then click Sounds.
2. Click **Required Files** to see every file name tt-Accessible looks for and the event it's used
   for.
3. Prepare a folder of WAV files with those names. Any file you leave out falls back to the Default
   pack.
4. Click **New Pack**, then select your folder. Its name becomes the name of the pack.
5. With your pack selected, use **Edit selected pack** to replace a single sound: click **Choose**
   next to an event to point it at another file, or **Reset** to go back to the default.

To see where your packs are stored, click **Reveal Packs Folder**. To remove one, select it, then
click Delete — a custom pack is also deleted from your Mac.

## Choose what VoiceOver announces

1. Open Preferences, then click Announcements in the sidebar.
2. Under Event announcements, select or deselect **Announce channel messages**, **Announce private
   messages** and **Announce broadcast messages**.
3. Click **Announce system history** to unfold twenty more events, grouped as Connection, Own
   channel, User presence, Moderation, Status, Subscriptions, Files and Media streaming. Use
   **Enable all** or **Disable all** to set them together.

Turning an event off only silences the announcement — the entry still appears in the session
history.

## Choose what happens when another app is in front

1. Open Preferences, then click Announcements.
2. Click the **Mode** pop-up menu, then choose one of the following:
   - **System notification** — a standard macOS notification.
   - **macOS text to speech** — tt-Accessible speaks the message itself.
   - **VoiceOver via AppleScript** — VoiceOver announces the message.
3. To use different modes depending on what arrives, deselect **Use the same mode for all event
   types**, then set private messages, channel messages, broadcast messages and TeamTalk history
   separately.

If you chose macOS text to speech, set the **Voice**, the **Speech rate** and the **Volume** just
below, then click **Test voice** to hear the result.

**See also:** [Get to know the tt-Accessible window](main-window.html) ·
[Change tt-Accessible settings](preferences.html#prefs-announcements)
