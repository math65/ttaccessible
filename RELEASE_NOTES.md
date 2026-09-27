## v1.13.0-beta.1 (build 57) — 2026-09-27

The volume sliders are back in the window, you can stream several sources from your Mac at once, and the connected window is easier to move through with VoiceOver. Most of this beta is the work of Rocco Fiorentino.

### Volumes
- **The volume sliders are back in the window**, just above the mixer: output, input, sound effects and media. Several people asked for them. The General strip in the mixer is gone.
- **Tab stops once on each slider**, and VoiceOver reads its name. Each slider has a "Reset to 50%" action.

### Streaming from your Mac
- **Stream several sources at once.** Tick any mix of devices and apps: a microphone and your music player, two audio interfaces, VoiceOver and an app. They go out as one stream.
- **A new list to pick sources from**, with a search field and three groups: Recently used, Devices and Applications. Your last five sources are in Recently used.
- **Nothing is ticked the first time you open it**, so nothing goes out until you choose.
- **Option+Command+A now starts and stops streaming.** While anything is streaming, the same key stops it, whether it is sound from your Mac, a file or an address. Option+Command+Period no longer does anything.
- **Loud sources no longer distort when they add up.** The peaks are brought down smoothly.
- **An app no longer cuts out for half a second** when it starts playing a new sound, such as a Quick Look preview.

### VoiceOver
- **The connected window is no longer a group you have to step into.** VoiceOver goes straight from the sidebar to the sliders, the mixer, the chat and the history, with no divider in the way.
- **The microphone button says its name**, Enable microphone or Mute microphone. It used to repeat the audio status instead.
- **Command+Shift+A answers straight away**, together with its sound, and no longer says "Toggle microphone" first.
- **A channel with a topic is read once.** It was read twice.
- **In the mixer, pressing a key twice only says the new value.** It used to say the old one first.
- **Command+5 in an empty channel tells you nobody else is there.**
- Sheet titles can be reached as headings.

### Audio devices
- **Unplugging your chosen device no longer loses it.** It stays in the menu, marked "not connected", and the app goes back to it as soon as you plug it in again. You can still choose System Default if you want to.
- **Sound comes back after you replug a device**, or after macOS restarts its audio. Before, you could be left with no sound at all.
- **Notification sounds follow your output device** when it comes back, and when the system default changes.
- **If your microphone was on, it turns back on with its device**, with the usual sound. That only happens if you are still on the same server, and have not turned the mic on or off or picked another one in the meantime.
- **The microphone preview in Preferences now plays while you are muted.**

### Fixes
- **Editing an old saved server could fail** with the message "Invalid attempt to change the owner of this item". The change now saves. Reported by Vlad.
- **Recording a key in Preferences works with Command+Shift+A.** Pressing it used to turn your microphone on or off instead.
- The help has been checked page by page against the app, in English and in French.

### Known
- The microphone turning back on after a replug has not been tried with a real device yet.
- Server error messages are still in English, whatever language you use the app in.

### Install

If you turned on "Include beta versions" in Preferences > General, tt-Accessible will offer you this update. To install it by hand:

1. Download `ttaccessible-1.13.0-beta.1-57.zip` below.
2. Unzip it and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Open it. The app is notarized, so macOS won't warn you.

### Download
[ttaccessible-1.13.0-beta.1-57.zip](https://github.com/math65/ttaccessible/releases/download/v1.13.0-beta.1/ttaccessible-1.13.0-beta.1-57.zip)

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
