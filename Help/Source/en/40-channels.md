---
title: Channels
description: Join and leave channels, create or edit them, set the audio codec, and exchange files.
keywords: channel, join, leave, create, edit, delete, password, codec, Opus, files, upload, download
anchor: channels
---

## Joining and leaving

- **Command-J** joins the channel selected in the tree; **Return** on the row does the same.
- **Command-L** leaves the channel you are in.

The app confirms out loud — *Joined channel: …* or *Left channel.* — and the session history keeps
a record.

If the channel is protected, the app asks for its password. Once you have entered the right one it
is saved, so the next visit is silent. **Forget Saved Password**, in the tree's context menu, clears
it again.

Two options in [Preferences → Connection](preferences.html#prefs-connection) automate this:
*Automatically join the main channel on connect* and *Automatically rejoin the last channel after
reconnecting*. A saved server can also carry a **Channel to join** of its own.

## Creating and editing a channel

| Shortcut | Command |
|---|---|
| F7 | Create Channel |
| Shift-F7 | Edit Channel |
| F8 | Delete Channel |

Deleting is permanent: *The channel and all its subchannels will be deleted.*

The channel form contains:

- **Channel name** and **Topic**.
- **Password** — leave empty for an open channel.
- **Maximum users**.
- **Disk quota for files**, in KB, MB or GB. A quota of 0 means only administrators can upload.
- **Permanent channel** — the channel survives when the last person leaves.
- **Solo transmit (one speaker at a time)**.
- **Disable voice activation (push-to-talk only)**.
- **No audio recording** — see [Recording](recording.html).
- **Join channel after creation**, when creating.

### Audio codec

The **Audio Codec** section configures the Opus encoder used by everyone in the channel:

- **Audio channels** — Mono or Stereo.
- **Sample rate**.
- **Bitrate (kbps)** — higher means better quality and more bandwidth.
- **Application mode** — **VoIP** for speech, **Music** for music.

Settings that the form does not show are preserved as they were when you edit an existing channel.

## Channel files

**Server → Channel Files** (**Shift-Command-F**) opens the file list of the channel, with the
**Name**, **Size** and **Uploaded by** of each file.

- **Upload…** sends a file — also available as **Server → Upload a File…** (**Shift-F5**).
- **Download** saves the selected file. **Return** does the same.
- **Delete** removes it from the channel, after confirmation. The **Delete** key works too.

Transfers report their progress and announce *Upload complete* or *Download complete* when they
finish. If the channel has no room left, the app reports *This channel does not have enough
storage.*

Files added or removed by other people appear in the session history and can be announced.
