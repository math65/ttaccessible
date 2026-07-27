---
title: Manage users, bans and server settings
description: Promote channel operators, kick or ban people, move them between channels, and edit accounts and server properties.
keywords: operator, kick, ban, move users, accounts, rights, server properties, statistics, admin
anchor: administration
---

If your account has the matching rights, you can moderate the channels of a server and change its
settings. Commands you aren't allowed to use stay dimmed.

## Make someone a channel operator

Select the person in the channel tree, then press Control-Command-O. Press it again to revoke the
status. If you aren't an operator yourself and the channel has an operator password, tt-Accessible
asks for it.

## Remove someone from a channel or the server

Select the person, then do one of the following:

- **Remove them from their channel:** press Command-K.
- **Disconnect them from the server:** press Shift-Command-K.
- **Disconnect and ban them:** choose User > Kick and Ban, then choose whether to ban the IP address
  or the user name.

Each command asks you to confirm. To skip that step for the two kick commands, open Preferences,
click Connection, then select **Skip confirmation when kicking users**. Kick and Ban always
confirms.

## Move people to another channel

- To move one person, select them and press Option-Command-X, then choose the destination channel.
- To move a whole channel, Control-click it, then choose **Move all in channel**. Select the people
  to move — **Select All** and **Deselect All** help — choose the destination in the **Move to
  channel** pop-up menu, then click Move.

## Manage bans

1. Choose Server > Banned Users, or press Shift-Command-B.
2. Do any of the following:
   - **Lift a ban:** select it, then click Unban. The person can reconnect.
   - **Add a ban:** click Add Ban, then choose **IP Address** or **Username** and enter the value.
   - **Update the list:** click Refresh.

## Manage user accounts

1. Choose Server > User Accounts, or press Shift-Command-U.
2. Click Add, or select an account and click Edit.
3. In the Essential tab, set the user name, password, account type — **Default**, **Administrator**
   or **Disabled** — an initial channel and a note.
4. In the Rights tab, select what the account may do. Twenty-four rights are available, covering
   logging in several times at once, seeing every user, creating and modifying channels,
   broadcasting, kicking, banning, moving people, becoming a channel operator, uploading and
   downloading files, changing server properties, transmitting voice, video, desktop and media
   files, locking the nickname or status, recording voice, seeing hidden channels, and sending
   private or channel messages. **Enable all**, **Disable all** and **Default rights** set them in
   one click.
5. In the Advanced tab, set the audio bandwidth limit, where 0 means unlimited, and the command
   limits.
6. Click Save.

To remove an account, select it and click Delete. You can't undo this.

## Change the server's settings

1. Choose Server > Server Properties, or press Shift-Command-P.
2. In the General section, set the server name, the message of the day, the maximum number of users,
   the timeouts and the login limits.
3. In the Bandwidth Limits section, set the maximum throughput for voice, video, media files,
   desktop sharing and the total, in bytes per second, where 0 means unlimited.
4. Click Save.

The Network & Server Information section shows the ports and versions for information.

To make the current configuration survive a restart of the server, choose Server > Save Server
Configuration.

## See how the server is doing

Choose Server > Server Statistics, or press Shift-Command-I, to see the uptime, the number of users
served, the peak, the data sent and received, and the UDP and TCP ping.

**See also:** [Adjust what you hear from each person](users.html) ·
[Join and manage channels](channels.html)
