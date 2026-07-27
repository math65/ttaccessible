---
title: Recording
description: Record a conversation as a single mixed file, as one file per person, or both.
keywords: recording, record, WAV, OGG, Opus, folder, stems, no recording, auto restart
anchor: recording
---

## Starting and stopping

| Shortcut | What it records |
|---|---|
| Command-R | A single mixed file, always |
| Shift-Command-R | Whatever **Recording mode** is set to in Preferences |

**Command-R** stops the recording again, and so does Shift-Command-R. The app announces *Recording
started* and *Recording stopped*, and the audio status (**F9**) reports whether a recording is
running. The toolbar has a matching button.

The first time, if no folder has been chosen, the app asks where to save the files.

## Recording mode

[Preferences → Recording](preferences.html#prefs-recording) sets what **Shift-Command-R** does:

- **Separate files (one per user)** — one file per person, including your own voice.
- **Both** — a mixed file *and* the individual files. This is the default.

**Command-R** is unaffected and always produces the single mixed file, which is why the two
shortcuts exist.

## Format and folder

- **Audio format** — **WAV** (the default, uncompressed) or **OGG (Opus)** (compressed, much
  smaller).
- **Recording folder** — chosen with **Choose…**, cleared with **Clear**. The app keeps its
  permission to write there across launches.

## Channels that forbid recording

A channel can be created with **No audio recording**. In such a channel, Command-R and
Shift-Command-R refuse to start and the app announces *Recording is not allowed in this channel* —
unless your account has the right to record voice.

## Restarting on its own

**Automatically restart recording when joining a channel** — off by default — resumes recording
when you join another channel, reconnect, or relaunch the app after a session that was being
recorded. The mode that was actually running is restored, so a Command-R recording comes back as a
single file rather than as the Shift-Command-R preference.

Changing channel during a mixed recording is handled for you: the current file is closed and a new
one is started in the new channel.
