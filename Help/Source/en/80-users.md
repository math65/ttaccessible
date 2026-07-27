---
title: People you hear
description: Adjust someone's volume, mute them locally, read their details, and choose what you receive from them.
keywords: user, volume, balance, mute, subscriptions, intercept, user information, connected users
anchor: users
---

Every command on this page applies to the person selected in the channel tree, and is available both
from the **User** menu and from the tree's context menu.

## Volume and balance

**Command-U** — *Adjust volume…* — opens a dialog with two sliders, **Voice** and **Media file**,
plus the stereo balance between the **Left speaker** and the **Right speaker**. Changes are applied
as you move the slider, so you can set the level while the person is talking. Cancel restores what
was there before.

The scale is even from end to end: *0% = silence · 50% = normal volume · 100% = maximum volume*.

Whether these adjustments are remembered is up to *Per-user volume memory* in
[Preferences → Audio](preferences.html#prefs-audio): never, for the session only, or always. Levels
are kept per server, so a setting made on one server never carries over to another.

For a faster, hands-on way to balance a whole channel, see [The channel mixer](mixer.html).

## Muting someone locally

- **Shift-Command-M** — *Mute locally* / *Unmute locally*. Only you stop hearing them.
- **Control-Shift-Command-M** — *Mute media stream locally*, which silences the media file someone
  is streaming while leaving their voice audible.

Both are announced, and both are local to your Mac: the person is not told.

## User information

**Command-I** opens **User Information** for the selected person: ID, nickname, username, status
mode and message, gender, user type, whether they are a channel operator, IP address, client,
version, and voice packet loss.

## Everyone on the server

**Server → Connected Users…** (**Shift-Command-W**) lists everyone connected, not just your channel,
with their nickname, status message, username, channel, IP address, version and ID. From there you
can view a person's information, copy it, send a private message, or — with the right permissions —
move, kick or ban them.

## Subscriptions

The **User → Subscriptions** submenu decides what you receive from the selected person. Each entry
is a switch you can turn on or off:

| Shortcut | Subscription |
|---|---|
| Control-1 | Private Messages |
| Control-2 | Channel Messages |
| Control-3 | Broadcast Messages |
| Control-4 | Voice |
| Control-5 | Desktop |
| Control-6 | Media File |

Turning **Voice** off for someone is a server-side unsubscribe: their audio is no longer sent to you
at all, unlike a local mute.

### Intercepts

Below them, the same submenu offers the intercepts, which require the corresponding rights and let
an administrator receive what is not addressed to them:

| Shortcut | Intercept |
|---|---|
| Control-Shift-1 | Intercept Private Messages |
| Control-Shift-2 | Intercept Channel Messages |
| Control-Shift-4 | Intercept Voice |
| Control-Shift-5 | Intercept Desktop |
| Control-Shift-6 | Intercept Media File |

The subscriptions applied to everyone when you connect are set in
[Preferences → Connection](preferences.html#prefs-connection), under **Default subscriptions** and
**Default intercepts**.
