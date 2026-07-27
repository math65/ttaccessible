---
title: Record a conversation
description: Record a channel as a single mixed file, as one file per person, or both, and choose where the files go.
keywords: recording, record, WAV, OGG, Opus, folder, stems, no recording, auto restart
anchor: recording
---

You can record what's said in a channel. tt-Accessible can mix everyone into a single file, write
one file per person, or do both at once.

## Start and stop a recording

- To record a single mixed file, press Command-R.
- To record using the mode set in Preferences, press Shift-Command-R.

Press the same shortcut again to stop. tt-Accessible announces *Recording started* and *Recording
stopped*, and F9 tells you whether a recording is running. The toolbar has a matching button.

The first time, if you haven't chosen a folder, tt-Accessible asks where to save the files.

## Choose what Shift-Command-R records

1. Open Preferences, then click Recording in the sidebar.
2. Click the **Recording mode** pop-up menu, then choose one of the following:
   - **Separate files** — one file per person, including your own voice.
   - **Both** — a mixed file and the individual files.

Command-R is unaffected: it always produces the single mixed file. That's why there are two
shortcuts.

## Choose the format and the folder

1. Open Preferences, then click Recording.
2. Click the **Audio format** pop-up menu, then choose **WAV** for uncompressed files or **OGG
   (Opus)** for much smaller ones.
3. Click **Choose**, then select the folder where recordings should go. tt-Accessible keeps its
   permission to write there from one launch to the next.

## Resume recording on its own

Select **Automatically restart recording when joining a channel** to pick recording back up when you
change channel, when the connection returns, or when you open tt-Accessible after a session that was
being recorded. The mode that was actually running is restored.

Changing channel during a mixed recording is handled for you: the current file is closed and a new
one starts in the new channel.

## If a channel forbids recording

A channel can be created with **No audio recording**. There, Command-R and Shift-Command-R refuse to
start and tt-Accessible announces *Recording is not allowed in this channel* — unless your account
has the right to record voice.

**See also:** [Join and manage channels](channels.html) ·
[Change tt-Accessible settings](preferences.html#prefs-recording)
