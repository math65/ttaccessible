---
title: Administration
description: Channel operators, kicks and bans, moving people, user accounts, server properties and statistics.
keywords: operator, kick, ban, move users, accounts, rights, server properties, statistics, admin
anchor: administration
---

The commands on this page need the matching rights on your account. Those you are not allowed to use
stay greyed out.

## Channel operator

**Control-Command-O** promotes the selected person to channel operator, or revokes it. If you are
not an operator yourself but the channel has an operator password, the app asks for it. The change
is announced: *… is now channel operator*.

## Kicking

| Shortcut | Command |
|---|---|
| Command-K | Kick from Channel — the person is removed from their current channel |
| Shift-Command-K | Kick from Server — the person is disconnected entirely |
| — | Kick and Ban — kick, then ban by **IP address** or by **username** |

Each one asks for confirmation. *Skip confirmation when kicking users* in
[Preferences → Connection](preferences.html#prefs-connection) removes that step for the two kick
commands; Kick and Ban always confirms.

## Moving people

- **Option-Command-X** — *Move to a channel…* — moves the selected person to a channel you pick.
- **Move all in channel…**, in the tree's context menu, moves a whole channel at once. The sheet
  lists everyone with a checkbox, offers **Select All** and **Deselect All**, and a **Move to
  channel:** menu. The result is announced once: *Moved n of n users to …*

## Bans

**Server → Banned Users…** (**Shift-Command-B**) lists the bans of the server: nickname, username,
type, date, who issued it, channel and IP address. From there you can **Refresh** the list,
**Unban** the selected entry — *This person will be able to reconnect to the server* — or **Add
Ban…** by **IP Address** or by **Username**.

## User accounts

**Server → User Accounts…** (**Shift-Command-U**) lists the accounts declared on the server, with
their username, the nickname currently online, the password, the type (**Default**,
**Administrator** or **Disabled**), a note and the last login.

**Add…** and **Edit…** open a form with three tabs:

- **Essential** — username, password, account type, initial channel, note.
- **Rights** — twenty-four switches, with **Enable all**, **Disable all** and **Default rights**.
  They cover logging in several times at once, seeing every user, creating temporary channels,
  modifying channels, broadcasting, kicking, banning, moving people, becoming channel operator,
  uploading and downloading files, modifying server properties, transmitting voice, video, desktop
  and media files, locking the nickname or the status, recording voice, seeing hidden channels, and
  sending private or channel messages.
- **Advanced** — audio bandwidth limit (0 means unlimited), commands limit and interval.

Deleting an account cannot be undone.

## Server properties

**Server → Server Properties…** (**Shift-Command-P**) opens the server's own settings in three
sections:

- **General** — server name, message of the day, maximum users, user timeout, login delay, maximum
  login attempts, maximum logins per IP, auto save.
- **Bandwidth Limits** — maximum voice, video, media file streaming, desktop sharing and total
  throughput, in bytes per second, where 0 means unlimited.
- **Network & Server Information** — TCP and UDP ports, server version and protocol version, shown
  for information.

**Server → Save Server Configuration** writes the current configuration on the server so that it
survives a restart.

## Statistics

**Server → Server Statistics** (**Shift-Command-I**) reports the uptime, the total number of users
served, the peak, the data sent and received in total and for voice, and the UDP and TCP ping.
