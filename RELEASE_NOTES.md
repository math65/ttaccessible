## v1.12.0 (build 56) — 2026-09-04

The connected window has been rebuilt into two panes, every volume in the app now lives inside the channel mixer, and the app speaks Turkish. If you have been on the stable channel since 1.11.1, this release also brings you everything the 1.12 betas have been testing all summer.

### Highlights
- **The connected window is now two panes instead of one tall column** — and VoiceOver reads it in exactly the same order as before.
- **Every volume in the app now lives in the mixer**, on a strip called General, reachable with Command+5.
- **The app is fully localised in Turkish**, and no longer falls back to French for people whose language it doesn't ship.
- **A microphone that stops being transmitted restarts itself, and says so** instead of leaving you silent for hours.
- **Ban and kick follow the rights your server actually gave you**, not just the administrator flag.

### The connected window and the mixer
- **Two panes.** The server name, its status lines, the microphone button and the channel tree sit in a sidebar; the mixer, chat, message box and history fill the rest. The divider can be dragged and is remembered between sessions. The reading order has not changed — VoiceOver walks the sidebar first, then the content pane, exactly as before.
- **The mixer is reachable again.** VoiceOver used to walk straight past it.
- **Every global level is on the General strip** — output, media, microphone and sound effects, in that order. Command+5 lands you there. Left and Right choose which level you are on, Up and Down move it, V speaks it, V twice puts it back to normal, and M mutes or unmutes everything. The four sliders that used to sit in the window are gone: those levels now exist in one place instead of two.
- **One level for every media stream at once.** When someone streams music into a channel while people are talking, Command+Shift+Up and Down turns the music down on its own, from anywhere in the window, without touching a single person's voice. A stream that starts afterwards is caught automatically, and your own stream goes down with everyone else's.
- **The keys move levels the way you would expect.** The arrows move by 1%, Page Up and Page Down by 10%, and Home and End go straight to 100% and 0%. Two percent per press was too coarse to land on a value, and reaching either end took fifty presses. Home, End and the page keys act on whichever level the arrows act on, so they work on a person's strip and on the General strip alike.
- **Windows open at the size they were meant to have.** Several opened at a fraction of it.

### Your microphone
- **A microphone that stops being transmitted now restarts itself, and tells you.** It could previously stay mute for hours without a single sign that anything was wrong.
- **A reconnect no longer swallows the microphone you had open.** It comes back the way you left it.
- **A channel that carries no voice now says so**, instead of opening a microphone into nothing.
- **New: you can choose to always arrive with the microphone off.** Preferences > Connection, off by default. Until now the app always gave you back the microphone the last session left open, which on a busy server means broadcasting first and finding out afterwards. Changing channel is unaffected, and a channel that confiscated your microphone still gives it back.

### Languages
- **Turkish.** All 1,200 strings, including every announcement, not just the menus. Choose it in Preferences > General > Language, or let the app follow a Mac already set to Turkish. Asked for by Serkan Türkyılmaz. It has not yet been read by a native speaker, so corrections are very welcome.
- **The app no longer falls back to French.** It declared French as its fallback language, so anyone whose Mac was set to a language the app doesn't ship — Turkish, German, Spanish — got a French app, and the Language preference could not repair the menus macOS draws itself. The fallback is now English.
- **French units and the French colon are no longer served to English-speaking users** in server statistics, file sizes, transfer footers and chat lines.

### People and moderation
- **Show people by nickname, by username, or by both.** A new menu in Preferences > General, applying everywhere someone is named: the channel tree and its order, chat lines, announcements, the history, private conversation titles, the Connected Users window and the mixer strips. It takes effect immediately, without reconnecting, and when the name you chose is empty the other one is shown. This preference now sits in Preferences > Connection, next to "Sort channels by".
- **Ban and kick follow the server's rights.** A moderator granted the right without the administrator flag can finally use them.

### Fixes
- **A refused action shows you the reason instead of quitting the app** — a crash present in every release since 1.10.0. Also released on its own as 1.11.1.
- **macOS 12:** the app menu keeps Quit, Services, Hide, Hide Others and Show All, and the Edit menu is built. Reported and patiently re-tested by Ron J.
- **Media streaming no longer runs on five milliseconds of margin**, which is what made it stop for no visible reason.
- **The addresses of streams you have already played are offered back to you.** Press Return to start one again.
- Typing a space in the General preferences no longer deletes it, and someone with no nickname is named rather than showing up as an empty line.

### Install

tt-Accessible will install this update for you automatically. To install by hand:

1. Download `ttaccessible-1.12.0-56.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.

### Download
[ttaccessible-1.12.0-56.zip](https://github.com/math65/ttaccessible/releases/download/v1.12.0/ttaccessible-1.12.0-56.zip)
