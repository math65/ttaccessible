---
title: Join and manage channels
description: Join and leave channels, create or edit them, set the audio codec, and exchange files with the people there.
keywords: channel, join, leave, create, edit, delete, password, codec, Opus, files, upload, download
anchor: channels
---

A channel is where you talk. You can join any channel on the server, create your own, and exchange
files with the people in it.

## Join or leave a channel

1. Select a channel in the tree.
2. Press Command-J, or press Return.

If the channel is protected, enter its password. tt-Accessible remembers it, so your next visit
asks nothing. To forget it, Control-click the channel, then choose **Forget Saved Password**.

To leave the channel you're in, press Command-L.

To join a channel automatically, open Preferences, click Connection, then select **Automatically
join the main channel on connect** or **Automatically rejoin the last channel after reconnecting**.
A saved server can also carry a channel of its own — see [Add a server](servers.html).

## Create a channel

1. Press F7.
2. Enter a channel name and, if you want one, a topic.
3. To protect the channel, enter a password.
4. Set the maximum number of users and the disk quota for files. A quota of 0 means only
   administrators can upload files.
5. Select any of the following options:
   - **Permanent channel** — the channel survives when the last person leaves.
   - **Solo transmit** — only one person speaks at a time.
   - **Disable voice activation** — people must use push-to-talk.
   - **No audio recording** — see [Record a conversation](recording.html).
6. To set the audio quality of the channel, use the Audio Codec section: choose **Mono** or
   **Stereo**, a sample rate, a bitrate in kbps, and **VoIP** or **Music** depending on what people
   will send.
7. Select **Join channel after creation** if you want to go there straight away, then click Create.

To change a channel, select it and press Shift-F7. Settings that the form doesn't show are kept as
they were.

To delete a channel, select it and press F8, then confirm. The channel and all of its subchannels
are deleted, and you can't undo this.

## Share files with the channel

1. Choose Server > Channel Files, or press Shift-Command-F.
2. Do any of the following:
   - **Send a file:** click Upload, or choose Server > Upload a File (Shift-F5).
   - **Get a file:** select it, then click Download or press Return.
   - **Remove a file:** select it, then click Delete or press the Delete key, and confirm.

tt-Accessible announces each transfer when it finishes. If the channel has no room left, it reports
*This channel does not have enough storage.*

**See also:** [Talk in a channel](talking.html) ·
[Manage users, bans and server settings](administration.html)
