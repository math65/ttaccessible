---
title: Adjust what you hear from each person
description: Set someone's volume, mute them for yourself, read their details, and choose what you receive from them.
keywords: user, volume, balance, mute, subscriptions, intercept, user information, connected users
anchor: users
---

Every command on this page applies to the person selected in the channel tree. You'll find them all
in the User menu, and in the shortcut menu of the tree.

## Set someone's volume

1. Select the person in the channel tree.
2. Press Command-U.
3. Drag the **Voice** and **Media file** sliders, and set the balance between the left and right
   speaker. Changes apply as you drag, so you can set the level while the person is talking.
4. Click Apply. To go back to the previous levels, click Cancel.

The scale is even from end to end: 0% is silence, 50% is the normal volume, and 100% is the maximum.

To balance a whole channel more quickly, see [Balance a channel with the mixer](mixer.html).

## Mute someone for yourself

- To silence a person, press Shift-Command-M. Only you stop hearing them, and they aren't told.
- To silence only the media file they're streaming, press Control-Shift-Command-M. Their voice stays
  audible.

Press the same shortcut again to hear them again.

## See someone's details

Press Command-I. The User Information window shows their nickname, user name, status, gender,
account type, whether they're a channel operator, their IP address, their client and version, and
their voice packet loss.

To see everyone connected to the server rather than just your channel, choose Server > Connected
Users, or press Shift-Command-W. From there you can view a person's information, copy it, send them
a private message, or — with the right permissions — move, kick or ban them.

## Choose what you receive from a person

The User > Subscriptions submenu decides what a person can send you. Each entry is a switch.

| Shortcut | Subscription |
|---|---|
| Control-1 | Private messages |
| Control-2 | Channel messages |
| Control-3 | Broadcast messages |
| Control-4 | Voice |
| Control-5 | Desktop |
| Control-6 | Media file |

Turning **Voice** off unsubscribes you on the server: their audio is no longer sent to you at all,
unlike muting them locally.

The same submenu offers the intercepts — private messages, channel messages, voice, desktop and
media file — on Control-Shift-1, 2, 4, 5 and 6. They let an administrator receive what isn't
addressed to them, and require the matching rights.

To set what everyone sends you as soon as you connect, open Preferences, click Connection, then use
**Default subscriptions** and **Default intercepts**.

**See also:** [Balance a channel with the mixer](mixer.html) ·
[Send and read messages](messages.html)
