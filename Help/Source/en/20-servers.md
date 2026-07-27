---
title: Add a server and connect to it
description: Add, edit and sort your TeamTalk servers, import and export them, and sign in with a BearWare account.
keywords: server, saved servers, import, export, tt file, tt link, BearWare, web login, connect
anchor: servers
---

You can keep as many TeamTalk servers as you like in the TeamTalk Servers window, which lists each
one with its name, host, TCP and UDP ports, and whether the connection is secure. Passwords are
stored in your login keychain, not in the app's own files.

## Connect to a server

1. Go to the TeamTalk Servers window in tt-Accessible.
2. Select a server in the list with the arrow keys.
3. Press Return or F2. You can also choose Server > Connect, or click Connect in the toolbar.

Once you're connected, F2 disconnects you.

If the server refuses your user name or password, click **Edit Credentials** in the alert to correct
them and try again.

## Add a server

1. Choose Server > New Server, or press Command-N.
2. Enter the name you want to see in your list, then the host and the TCP and UDP ports.
3. Select **Encrypted connection** if the server requires it.
4. Enter a nickname, or leave the field empty to use your default nickname.
5. Enter your user name and password for that server, or leave them empty to connect as a guest.
6. To join a channel as soon as you connect, enter its path in **Channel to join**, and its password
   if it has one.
7. Click Save.

To change a server later, select it and press Command-E. To remove it, press Delete, then confirm.

## Sort the list of servers

Use the **Sort** pop-up menus above the list to order your servers by **Custom order**, **Name**,
**Host**, **TCP Port** or **UDP Port**, in **Ascending** or **Descending** order. Custom order keeps
the servers in the order you added them. Your choice is remembered.

## Import servers

1. Choose Server > Import TeamTalk Servers, or press Shift-Command-I.
2. Choose how to import:
   - **Configuration File** — a configuration file from the official TeamTalk client. All of its
     servers are imported at once.
   - **.tt File** — a single server file, the format server owners usually share.
   - **Paste tt:// Link** — paste a link such as `tt://server.example.com?tcpport=10333`.
3. If a server you're importing matches one you already have, click **Replace** to update it. When
   several entries match, click **Continue** to import them all.

tt-Accessible reports how many servers were imported and how many were skipped.

You can also open a `.tt` file from the Finder, or click a `tt://` link. If a session is already
open, tt-Accessible warns you that opening the file disconnects it. A server opened this way isn't
saved automatically: when you disconnect, tt-Accessible offers to save it under a name of your
choice.

## Export servers

- To export the selected server, choose Server > Export Server, then choose **.tt File** or **Copy
  tt:// Link**. While you're connected, you can also select **Include a direct path** so that
  whoever opens the file lands in the channel you're in.
- To export all of them, choose Server > Export Server List, then choose **Single file** or **One
  file per server**.
- To copy a link to the server you're connected to, choose Server > Copy Server Link, or press
  Shift-Command-L.

## Sign in with a BearWare account

A free BearWare account (bearware.dk) lets you log in to servers that support web login, without
creating an account on each one.

1. Open Preferences, then click BearWare in the sidebar.
2. Enter your **BearWare username** and **BearWare password**, then click **Sign in**.
3. Open the settings of each server that supports it, then select **Use BearWare web login**. The
   local user name and password fields disappear — that server now signs in with your BearWare
   account.

If a server is set to use web login while no BearWare account is set up, the connection fails and
tt-Accessible points you back to Preferences.

**See also:** [Get to know the tt-Accessible window](main-window.html) ·
[Join and manage channels](channels.html)
