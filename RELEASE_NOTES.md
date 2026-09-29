## v1.13.0-beta.2 (build 58) — 2026-09-29

A small beta about connecting to servers. The app now sends far fewer commands to the server when you log in, and it keeps a record of what happens when a server stops answering.

### Connecting
- **Logging in sends far fewer commands.** The app used to send two for every person on the server, whatever your settings: 34 for a server with 17 people. It now only sends what differs from the server's own settings, which usually means none at all, the same as the official TeamTalk app.
- **Changing a default subscription in Preferences only changes that one.** Say you turn off private messages by default: the people already on the server lose private messages and nothing else. Anything you set by hand for one person stays as it was.
- **Webcam video is no longer turned off for everyone at login.** The app now leaves it as the server sets it, like the official app does. It still doesn't show webcams.

### If a server stops answering
Some of you can log in to a server but never join a channel. After a few seconds you get "The server did not respond within the expected time", then you're disconnected a minute later. We don't know the cause yet. This beta writes what the connection is doing to the audio log, so we can see which side goes quiet.

If it happens to you, **don't quit the app**. Go to Help > Contact the Developer, choose "Report a problem", and tick "Attach the audio diagnostic log". The log is erased every time the app starts, so it has to be sent from the session where the problem happened.

### Known
- We haven't confirmed that this beta fixes the problem above. The log will tell us.

### Download
[ttaccessible-1.13.0-beta.2.zip](https://github.com/math65/ttaccessible/releases/download/v1.13.0-beta.2/ttaccessible-1.13.0-beta.2.zip)
