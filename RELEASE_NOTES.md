## v1.12.0-beta.1 (build 47) — 2026-08-10

This beta is about streaming. You can now send several applications into a channel at once — your music player and VoiceOver together, say — or simply everything this Mac plays. And a live broadcast finally says what it does: it never pretended to pause, it mutes the source, and the controls now word it that way.

### Highlights
- **Stream several applications at once**, VoiceOver among them.
- **Or all audio from this Mac**, in a single tick.
- **A live source mutes instead of pausing** — the broadcast stays up and goes silent, and the button says so.
- **No more elapsed time against a total of 00:00** on something with no end.

### Choosing what to stream
- **Option-Command-A is now "Stream Audio from This Mac"**, and opens a list of tick boxes instead of a pop-up menu with a single choice.
- **Applications cumulate.** Tick as many as you like, VoiceOver included, and they are mixed into one stream.
- **"All audio from this Mac"** sits at the top of the list. tt-Accessible's own output is left out of the capture, otherwise the channel would hear itself come back. Notifications and system sounds do go out. Requires macOS 13 or later.
- **An input device still streams on its own** — a different kind of capture entirely — so ticking one unticks the applications. Whatever a tick clears is spoken out loud.
- **Space ticks and unticks** the selected line, and the arrow keys move through the list.
- **Your last selection is restored**, even when it covered several applications.
- **"Mute this source on this Mac" is refused for all-system audio.** Muting that capture would silence the whole Mac, VoiceOver with it.

### The broadcast controls
- **A device, an application or VoiceOver cannot be paused**, because the stream keeps feeding the channel. The button now reads Mute and Unmute, and the broadcast stays up while the source is silent.
- **The position slider is gone when there is nothing to seek to** — a live capture, but an internet radio too. It used to read "02:31 / 00:00" and take adjustments it could not honour.
- **Every toggle is announced**, so you hear the new state even when the button doesn't have focus.
- **Option-Command-M silences a broadcast without ending it**, from anywhere in the app.
- **An arrow key with nowhere to seek to now says so** instead of doing nothing.
- **VoiceOver is no longer told an adjustment succeeded when it didn't** on a stream without a position.

### The user guide
- The streaming and shortcut pages are rewritten in both languages: the controls are in the main window and never were a separate window, the keys are listed for a media file and for a live source separately, and what can be ticked together is spelled out.

### Download
[ttaccessible-1.12.0-beta.1-47.zip](https://github.com/math65/ttaccessible/releases/download/v1.12.0-beta.1/ttaccessible-1.12.0-beta.1-47.zip)

## v1.11.0 (build 46) — 2026-08-04

This release adds a complete user guide to the Help menu, and rebuilds how global shortcuts work: a microphone shortcut no longer asks for a system permission, and the key you press no longer ends up typed into whatever app you were using. Setting a volume to 0% now really does mean silence.

### Highlights
- **A complete user guide, in the Help menu (⌘?)** — 18 topics, in English and French.
- **A microphone shortcut used from another app no longer needs the Input Monitoring permission.**
- **The key you press is now truly taken.** It no longer types into the app you are working in.
- **0% on a volume slider is silence.** It used to be a quiet — but perfectly audible — level.

### The user guide
- **⌘? opens a full guide in the macOS help viewer.** It covers the first launch, adding a server, moving around the main window, channels, talking, messages, the channel mixer, setting up your audio, recording, streaming, users and administration, every preference pane, sounds and announcements, profiles, the complete shortcut list, and what to do when something doesn't work.
- **Written to be followed, not read.** Each topic starts with what you can do, then gives numbered steps naming the exact menu, button and pop-up menu to use.
- **Available in English and French.** The help viewer picks its language from your Mac's, not from the app's, so each home page links to the other language if you end up in the wrong one.

### Microphone shortcuts from other apps
- **No more Input Monitoring permission** for an ordinary shortcut — a key with Command, Control or Option. Only a shortcut made of modifier keys alone (pressed and released on their own) still asks for it.
- **The key no longer reaches the app in front.** Previously your shortcut both toggled the microphone and typed its character into whatever you were using. Worth knowing: the app that used that same shortcut internally stops receiving it while yours is set — Reaper, for instance, loses its Control-Space for as long as you keep it bound.
- **A shortcut that would type is now refused while you record it**, with the alternatives spoken out: F13 to F20, or add Command, Control or Option. A shortcut of that kind saved before this release is refused too, and Preferences tells you why, rather than silently eating that letter everywhere you type.
- **The User menu now shows the shortcut you actually chose**, instead of always displaying ⌘⇧A.
- **F13 to F20 are named properly** — they used to appear as "Key 105" and could not be shown in the menu, when they are exactly the keys worth choosing.

### Fixes
- **A re-bound microphone shortcut now works with tt-Accessible in front too.** Once you changed it in Preferences, it worked everywhere except in the app itself.
- **The shortcut shown matches the key you pressed on AZERTY keyboards.** A ⌘⇧ shortcut on the "1" key was displayed as ⌘⇧& in the menu and ⌘⇧1 in Preferences — two labels for one shortcut, read aloud as two different things.
- **Your shortcut is no longer registered twice at launch.** Reported by Rocco Fiorentino.
- **VoiceOver now names two places it entered blind**: the rights table when editing a user account, which announced itself as "table" and nothing else, and the scrolling areas of the server properties and user information windows.
- **A microphone shortcut stops responding while a password field is focused anywhere on your Mac.** That is macOS protecting your typing, not a bug — it is now written down in the troubleshooting page.

### Download
[ttaccessible-1.11.0-46.zip](https://github.com/math65/ttaccessible/releases/download/v1.11.0/ttaccessible-1.11.0-46.zip)

## v1.10.0 (build 45) — 2026-07-26

This release lets you stream an application's audio — or VoiceOver itself — into a channel, and keeps your voice in time with it. Auto-reconnect now reliably puts you back in the channel you were in, channel passwords are remembered, and moderators can move a whole channel's occupants in one go.

### Highlights
- **Stream any application's audio into your channel** — or VoiceOver's — not just an input device. Press **⌥⌘A**.
- **Your voice stays in time with what you stream**, so listeners hear both together.
- **Auto-reconnect actually brings you back**, into the same channel, however many times the connection drops.
- **Channel passwords are remembered**, so a protected channel stops asking every time.

### Streaming an application or VoiceOver
- **⌥⌘A now offers three kinds of source**: an input device, VoiceOver, or a running application. Applications are grouped in their own submenu.
- **You can pick an application that isn't running yet.** Capture attaches by itself the moment it starts playing audio, and survives it quitting and relaunching mid-stream.
- **Optionally silence the source on your own Mac while you stream it**, so only the channel hears it. Off by default, and never remembered between streams.
- **Your voice is delayed to match the stream.** Streaming carries close to a second of latency, so without this you would arrive ahead of your own music or instrument. The delay is measured live and tracks drift while you talk.
- Applications and VoiceOver need macOS 14.2 or later. On macOS 13 to 14.1 only already-running applications can be captured, and macOS 12 offers input devices only.

### Reconnecting
- **A dropped connection now reliably reconnects, and puts you back in the channel you were in** — by path, so it still works when the server restarts and renumbers its channels.
- **It works every time, not only once per session.** A second drop used to leave you disconnected.
- **Being kicked or banned no longer reconnects you seconds later.**
- Attempts space themselves out — 5 seconds, then 10, 30 and 60 — and give up after about five minutes rather than hammering a server that is gone.

### Channel passwords
- **A protected channel you have joined once stops asking.** The password is kept in your keychain, per channel and per server.
- **This works at launch too**, so "rejoin last channel" no longer drops you in the root of the server because it had no password.
- **"Forget Saved Password"** on a channel's context menu, shown only when there is one to forget.
- **If the password changes on the server, the saved one is discarded** rather than being submitted again and pre-filled into the prompt.
- Repointing a saved server at a different host or port clears its channel passwords, so they are never sent to another server.

### Moderation
- **Move everyone in a channel at once**, from the channel's context menu — with a checklist so you can leave people behind, and a VoiceOver action on the channel row.
- The result is announced and reported once ("Moved 5 of 6 users to…"), instead of one dialog per person.
- **Destination channels are listed by their full path**, so two channels with the same name under different parents can be told apart. This applies to the existing single-user move as well.

### Fixes
- **Channel Mixer announcements are no longer cut off.** Volume, pan and mute changes were announced at the wrong priority since 1.7.0, so VoiceOver could talk over them.
- The mixer's announcements and the move dialog now read correctly when a channel holds a single person.

### Thanks
Nearly all of this was designed and built by **Rocco Fiorentino** — application and VoiceOver streaming, voice sync, reliable reconnection, channel passwords and bulk moves. Thanks as ever, and to everyone who keeps sending feedback.

### Download
[ttaccessible-1.10.0-45.zip](https://github.com/math65/ttaccessible/releases/download/v1.10.0/ttaccessible-1.10.0-45.zip)

## v1.9.0 (build 44) — 2026-07-24

This release rebuilds push-to-talk from the ground up: any key can be your talk key, it can work while you are busy in another app, and a new microphone mode lets you combine muting with push-to-talk. You can also now pick the app's language instead of following your Mac's.

### Highlights
- **Push-to-talk rebuilt.** Any key works — a single key on its own, or a combination of modifier keys.
- **Your talk key and the microphone toggle can work from any app**, not only when tt-Accessible is in front.
- **Choose the app's language** — English or French — instead of following your Mac.

### Push-to-talk
- **Any key can be your push-to-talk key.** A single key on its own, or a combination of modifier keys such as Command-Control (press it and let go). Setting it is one button: activate it, then press the key you want.
- **The key field is properly accessible now.** It is a real button that VoiceOver announces, and while you are recording a key it no longer trips over VoiceOver's own Control-Option presses.
- **New microphone mode: Both.** ⌘⇧A mutes and unmutes as it always did. On top of that, holding your push-to-talk key lets you talk even while muted, and releasing it puts you back to silence. Choose it in Preferences › Audio.
- **An optional sound when transmission starts and stops**, so you can hear that your key registered.
- **Hotkeys can work while another app is in front.** Switch it on separately for push-to-talk and for the ⌘⇧A microphone toggle. macOS asks for the Input Monitoring permission the first time.
- Worth knowing: the key still reaches the app you are working in — tt-Accessible can see it go by, but cannot keep it to itself. So prefer a combination of modifier keys on their own, such as Command-Control, or a function key between F13 and F19: neither one types anything anywhere. Avoid single letters.
- **⌘⇧A no longer fires while the Finder is in front.**
- The push-to-talk key you were already using is carried over automatically.

### Language
- **Preferences › General now has a Language setting** — System Default, English, or French. Restart the app to apply it everywhere.
- **The first time you launch the app, it asks which language you want.**

### Thanks
Push-to-talk was designed and built by **Rocco Fiorentino**. The language setting was contributed by **Gruia Chiscop**. Thanks to both — and to everyone who keeps sending feedback.

### Download
[ttaccessible-1.9.0-44.zip](https://github.com/math65/ttaccessible/releases/download/v1.9.0/ttaccessible-1.9.0-44.zip)

## v1.8.0 (build 43) — 2026-07-22

This release adds live audio-device streaming into a channel, brings back support for macOS 12 (Monterey), and fixes audio going silent in "no recording" channels — plus mixer and recording refinements.

### Highlights
- **Stream a live audio device into your channel.** Pick any input device — an audio interface, a virtual device, loopback — and broadcast it into the channel as a media stream alongside your voice. Press **⌘⌥A**.
- **macOS 12 Monterey is supported again.** The app now runs on macOS 12 and later.
- **Audio no longer goes silent in "no recording" channels.**

### Live device streaming
- **⌘⌥A** streams the selected input device into the current channel as a media stream, alongside your voice.
- It starts fast without freezing the channel, and stays low-latency — the stream uses Opus with very small frames so the server's analysis is near-instant.
- If the device goes quiet, silence is filled in automatically so the stream never drops out.

### Audio
- **"No recording" channels now play sound again.** In a channel flagged as no-recording, other people's voices were silent for you — even though they worked fine for people on the Qt or iPhone clients. That's fixed: you hear everyone again. Recording itself stays blocked in those channels, exactly as the server intends.

### Channel Mixer
- **Independent stereo placement (pan) for each person's voice and their media.** You can position someone's voice and their media stream separately in the stereo field.

### Recording
- **⌘R records a single mixed file; ⌘⇧R records per-person stems (or both).** The two shortcuts now pick the recording layout directly.
- Note if you used recording before: if you were on "single file", the toolbar button now records **both** a single file and per-person stems. Use **⌘R** for single-file only.

### Administration
- **Per-channel disk quota**, editable with a KB / MB / GB unit picker.
- **Full server properties** — TCP/UDP ports and version info — in the server properties window.
- **Online-nickname column** in the user accounts list.

### Accessibility & polish
- Clearer VoiceOver in the Channel Mixer: spoken region announcements and mute-state labels in the toolbar.
- **Escape closes auxiliary windows.**
- Smaller fixes: no false intercept sound during login sync, live disk-quota unit conversion, and file uploads are no longer wrongly rejected by a client-side quota check.

### Download
[ttaccessible-1.8.0-43.zip](https://github.com/math65/ttaccessible/releases/download/v1.8.0/ttaccessible-1.8.0-43.zip)

## v1.7.0 (build 42) — 2026-07-08

This is the stable release that brings everything from the 1.7.0 beta line to everyone. If you were on 1.6.0, here is what has changed.

### Highlights
- **A brand-new per-user Channel Mixer.** Every person in your channel gets their own voice volume, media volume, left/right placement, mute, and solo — all reachable from the keyboard and VoiceOver.
- **Sign in with a BearWare account.** Use a free bearware.dk login to connect to servers that support it, without creating a separate account on each one.
- **A rebuilt, faster, steadier audio engine.** Connecting is near-instant again, switching headphones or speakers no longer freezes the sound, and crowded channels stay smooth.

### The Channel Mixer
- Each user in the channel has their own strip: **voice volume, media volume, stereo placement (pan), mute, and solo**.
- Drive it entirely from the keyboard while focused on a person: Up/Down for voice volume, Command+Up/Down for their media volume, Left/Right to move them in the stereo field, and V, P, M, S to hear or reset volume, pan, mute, and solo.
- **New: press Command+5 to jump straight to the mixer** — it joins the Command+1 to Command+4 area shortcuts as a fifth focus target. (Thanks to Matthew Whitaker for the suggestion.)
- Each person's settings are remembered and come back the next time they join.

### Audio
- **Switching your output device no longer freezes the sound.** Change headphones or speakers while connected and the audio simply follows.
- **Connecting is quick again.** On Macs with a lot of audio gear, opening a connection used to stall for around 13 seconds while every device was checked — that scan is gone, and it is now baked into every build for good.
- **Crowded and high-quality channels stay smooth.** Channels using larger audio packets could sound choppy for everyone; the playback path was reworked so it holds up under load.
- **Your chosen microphone and output are remembered reliably**, surviving unplugging, replugging, and restarts instead of quietly landing on the wrong device.
- **Standalone noise reduction.** A new Microphone processing setting (Preferences › Audio) lets you pick None, Noise reduction, or Echo cancellation with noise reduction — and it applies live, even mid-transmission.
- **You can now hear your own streamed media** when you play an audio or video file into a channel.
- **Per-user volumes are now kept per server**, so volumes set on one server no longer bleed into another. A new setting lets you choose whether these are remembered always, only for the session, or not at all.

### Accessibility
- The app is now named **tt-Accessible** so VoiceOver and speech synthesizers pronounce it correctly.
- **Press VoiceOver+Space to join** the selected server or channel.
- **Sliders and the microphone button now speak their values** as you change them — gain, output volume, and the various Preferences sliders.
- Preferences reads more cleanly in VoiceOver: no duplicate labels, each section is a proper heading, scroll areas are named, and Escape closes the window.

### Fixes
- **BearWare web login connects reliably** on servers that respond in slightly non-standard ways.
- **An empty nickname** now falls back to your default instead of failing to connect.
- The app **launches faster**.

### Thanks
Huge thanks to **Rocco Fiorentino**, who designed and built the audio rewrite and the Channel Mixer, the accessibility and VoiceOver improvements, and the faster, steadier connecting in this release. Thanks to **Matthew Whitaker** for the Command+5 suggestion — and to everyone who tested the betas and sent feedback.

### Install

tt-Accessible will install this update for you automatically. To install by hand:

1. Download `ttaccessible-1.7.0-42.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.

### Download
[ttaccessible-1.7.0-42.zip](https://github.com/math65/ttaccessible/releases/download/v1.7.0/ttaccessible-1.7.0-42.zip)
