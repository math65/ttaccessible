## v1.11.1 (build 52) — 2026-08-28

A single fix, for a crash that has been in every release since 1.10.0: when the server refused something you asked for, the app quit instead of telling you why.

### The fix
- **A refused action now shows you the reason, instead of quitting the app.** Whenever the server turned down a request — editing a channel, kicking or moving a user, sending a message, transferring a file — the app was supposed to open an alert explaining what happened. Instead it closed on the spot, losing your connection and anything you were in the middle of. The alert now appears as it always should have, and it names the server's own reason for saying no.

Found thanks to a crash report sent in by **Ron J.**, who noticed it always happened on one particular channel and took the trouble to narrow it down.

### Install

tt-Accessible will install this update for you automatically. To install by hand:

1. Download `ttaccessible-1.11.1-52.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.

### Download
[ttaccessible-1.11.1-52.zip](https://github.com/math65/ttaccessible/releases/download/v1.11.1/ttaccessible-1.11.1-52.zip)
