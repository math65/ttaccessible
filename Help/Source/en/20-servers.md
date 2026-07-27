---
title: Servers
description: Add, edit, sort, import and export TeamTalk servers, and sign in with a BearWare account.
keywords: server, saved servers, import, export, tt file, tt link, BearWare, web login, connect
anchor: servers
---

The **TeamTalk Servers** window is where every session begins. It lists your saved servers with
their **Name**, **Host**, **TCP** and **UDP** ports, and whether the connection is **Secure**.

The window itself reminds you of the essentials: *Return or F2 to connect, Command-N to add,
Command-E to edit, Delete to remove.*

## Connecting

Select a server with the arrow keys and press **Return** or **F2**. The same command appears as
**Server → Connect**, and as the **Connect** button in the toolbar.

Once connected, **F2** becomes **Disconnect**.

If the server refuses your credentials, the app offers **Edit Credentials…** so you can correct the
username or password and try again without retyping everything else.

## Adding a server by hand

Press **Command-N**, or choose **Server → New Server**. The form asks for:

| Field | What it is |
|---|---|
| Name | How the server appears in your list |
| Host | The server address |
| TCP Port / UDP Port | The server's ports |
| Encrypted connection | Turn on if the server requires encryption |
| Nickname | The name others see. Leave empty to use your default nickname |
| Username / Password | Your account on that server. Leave empty for a guest login |
| Use BearWare web login | Sign in with your BearWare account instead (see below) |
| Channel to join | A channel path to join automatically after connecting |
| Channel password | The password for that channel, if it has one |

Passwords are stored in your login keychain, not in the app's own files.

To change a server later, select it and press **Command-E**. To remove it, press **Delete**; the app
asks for confirmation.

## Sorting the list

The **Sort** controls above the table order the list by **Custom order**, **Name**, **Host**,
**TCP Port** or **UDP Port**, either **Ascending** or **Descending**. Custom order keeps the servers
in the order you added them. The choice is remembered.

## Importing servers

Choose **Server → Import TeamTalk Servers…** (**Shift-Command-I**). The app asks how to import:

- **Configuration File...** — a configuration file from the official TeamTalk client. All its servers
  are imported at once. tt-Accessible can detect the file format on its own; the behaviour is
  controlled by *Automatically detect the TeamTalk file format during import* in
  [Preferences → General](preferences.html#prefs-general).
- **.tt File...** — a single server file, the format usually shared by server owners.
- **Paste tt:// Link...** — paste a link such as `tt://server.example.com?tcpport=10333`.

If a server you are importing matches one you already have, the app asks whether to **Replace** it.
When several entries collide, it asks once whether to **Continue**. At the end you get a summary:
*n server(s) imported, n skipped.*

You can also simply open a `.tt` file from the Finder, or click a `tt://` link. If a session is
already running, the app warns that *Opening "…" will disconnect the current session* before
continuing. When the file also carries client settings — a nickname or a gender — the app lists what
it can apply and lets you **Apply** or **Ignore** them.

A server opened this way is not saved automatically. When you disconnect, the app offers to
**Save** it under a name of your choice.

## Exporting servers

- **Server → Export Server...** exports the selected server as a **.tt File...** or copies a
  **tt:// Link** to the clipboard. When you are connected, the same command can *Include a direct
  path to* the channel you are in, so whoever opens the file lands in the right place.
- **Server → Export Server List…** exports everything, either as a **Single file** or as **One file
  per server** in a folder you choose.

While connected, **Server → Copy Server Link** (**Shift-Command-L**) puts a link to the current
server on the clipboard.

## BearWare web login

A free BearWare account (bearware.dk) lets you log in to servers that support web login, without a
separate account on each one.

1. Open [Preferences → BearWare](preferences.html#prefs-bearware).
2. Enter your **BearWare username** and **BearWare password**, then click **Sign in**. Once signed
   in, the pane shows *Signed in as …* and offers **Sign out**.
3. In each server that supports it, turn on **Use BearWare web login**. The local username and
   password fields disappear — that server now signs in with your BearWare account.

If a server is set to use web login while no BearWare account is configured, the connection fails
with a message pointing you back to Preferences.
