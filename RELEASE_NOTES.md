## v1.12.0-beta.6 (build 53) — 2026-08-28

Two fixes, both from testers' reports. One of them is a crash that has been in every release since 1.10.0, and it is also out today as v1.11.1 for everyone still on the stable channel.

### Fixes
- **A refused action now shows you the reason, instead of quitting the app.** Whenever the server turned down a request — editing a channel, kicking or moving a user, sending a message, transferring a file — the app was supposed to open an alert explaining what happened. Instead it closed on the spot, losing your connection and anything you were in the middle of. Found thanks to a crash report from **Ron J.**, who noticed it always happened on one particular channel and took the trouble to narrow it down.
- **The app menu really does have Services, Hide, Hide Others and Show All back on macOS 12.** Beta 5 claimed this and was wrong: the items were inserted, then SwiftUI rebuilt the menu and took them straight back out. They are now declared where the menu itself is built, the same cure that made Quit stick in beta 3. Reported, and disproved, by **Ron J.**

### Known
Error messages coming from the server are still shown in English, whatever language you use the app in — "Command not authorized" and its 44 siblings come from the TeamTalk library untranslated. Now that these alerts appear at all, translating them is next.

### Install

tt-Accessible will install this update for you automatically. To install by hand:

1. Download `ttaccessible-1.12.0-beta.6-53.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.

### Download
[ttaccessible-1.12.0-beta.6-53.zip](https://github.com/math65/ttaccessible/releases/download/v1.12.0-beta.6/ttaccessible-1.12.0-beta.6-53.zip)
