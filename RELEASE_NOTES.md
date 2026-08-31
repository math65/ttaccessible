## v1.12.0-beta.7 (build 54) — 2026-08-31

The connected window has been rebuilt, and every volume in the app now lives inside the mixer. This is the largest layout change since tt-Accessible shipped — and nobody has listened to it yet in a real channel. That is what this beta is for.

### New
- **The connected window is now two panes instead of one tall column.** The server name, its status lines, the microphone button and the channel tree sit in a sidebar; the mixer, chat, message box and history fill the rest. The divider between them can be dragged and is remembered. **The reading order has not changed** — VoiceOver walks exactly the same sequence as before, sidebar first, then the content pane. The only new thing you will meet is the divider itself.
- **Every global volume now sits at the head of the mixer, on a strip called General.** Output, media, microphone and sound effects, in that order. Press Command+5 and that is where you land. Left and Right pick which level the arrows act on, Up and Down move it, V says it out loud, V twice puts it back to normal, and M mutes or unmutes everything. The four sliders that used to sit in the window are gone — the General strip replaces them, for the mouse just as much as for the keyboard, and those levels now exist in one place instead of two.
- **One level for every media stream at once.** When somebody streams music into a channel while people are talking, you can now turn the music down on its own — without touching a single person's voice, and without going through the mixer person by person. Command+Shift+Up and Down adjusts it from anywhere in the app, so you can duck the music in the middle of a conversation. A stream that starts afterwards is caught automatically, and your own stream is turned down along with everyone else's. Suggested by **Yannick**.

### Fixes
- **Banning and kicking now follow the rights your server gave you, rather than whether you are an administrator.** An account holding the ban and unban rights, without being a full admin, found the options dimmed and was told nothing. The server has always asked for the right, not for the account type; the app asked the wrong question in six places — the Banned Users window, Kick from server and Kick and ban, both in the User menu and in the channel tree, and their twins in the Connected Users window, where holding one right without the other showed you both or neither. Reported by **David**.
- **Sizes and durations were shown in French, whatever language you run the app in.** The server statistics reported an uptime of "10j 6h 35min" and a total sent of "37.6 Go" — French abbreviations, reaching English users untouched. The file sizes in Channel Files did the same. So did the space French puts before a colon, which turned up in the statistics labels, in the ban dialog, and in every chat line VoiceOver reads out. English now gets "10d 6h 35min", "37.6 GB", and no space before the colon; French is unchanged. The file-transfer footer was in the same state — VoiceOver announced it in French to everyone — and is now translated too. Reported by **Ron J.**
- **Windows that opened far smaller than they were meant to.** Preferences opened as a bare title bar — no sidebar, no panes, nothing to click. Channel Files opened at a third of its width, with file names cut short and the Size and Uploader columns off-screen. Connected Users simply did not show its IP Address, Version and ID columns. Also fixed along the way: the private-message field used a third of its row, and the channel sheet cut its sample-rate and disk-quota labels mid-sentence. Found by opening every window and looking at it, which nobody had done — this app is built for VoiceOver, and none of these defects makes a sound.
- **VoiceOver went straight past the mixer.** Moving forward with VO+Right jumped over it entirely, while moving backward found it. Two elements sat at the same place, and VoiceOver kept the empty one.
- **The mixer's letter keys no longer feel slow.** They used to wait a third of a second on every press, in case a second one was coming. And holding M down no longer toggles mute over and over.

### Known
- **None of this has been heard yet in a busy channel.** The layout is right on screen and correct in the accessibility tree, but whether it is pleasant to navigate is not something a screenshot can tell. If something is awkward, say so — that is the feedback this beta is asking for.
- On a person's strip, VoiceOver reads the percentage twice.
- The ban and kick fix needs an account that holds the right without being an administrator, and nobody has confirmed it against a live server yet.
- Server error messages are still shown in English whatever language you use the app in. They come from the TeamTalk library untranslated; translating them is still next.

### Install

tt-Accessible will install this update for you automatically. To install by hand:

1. Download `ttaccessible-1.12.0-beta.7-54.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.

### Download
[ttaccessible-1.12.0-beta.7-54.zip](https://github.com/math65/ttaccessible/releases/download/v1.12.0-beta.7/ttaccessible-1.12.0-beta.7-54.zip)
