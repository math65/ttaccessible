---
title: If something doesn't work
description: What to check when you can't hear anyone, when nobody hears you, when there's echo, and how to reach the developer.
keywords: problem, no sound, microphone, echo, permission, keychain, log, support, bug report
anchor: troubleshooting
---

Most audio problems come down to a handful of settings. Press F9 at any time to hear the current
audio status — it answers the first question for you.

## If you can't hear anyone

1. Check that the master volume isn't muted: press Command-M.
2. Check the **Output volume** slider in the main window.
3. Open Preferences, click Audio, then check that **Output device** isn't set to **No output
   device** or to a device you no longer use. Click **Refresh Devices** to rebuild the list.
4. Check whether that person is muted for you: their row says *muted*, and Shift-Command-M brings
   them back. Check their level in [the mixer](mixer.html) too.
5. Check that you're still subscribed to their voice — see
   [Adjust what you hear from each person](users.html).

## If nobody hears you

1. Check that you've joined a channel. Outside one, tt-Accessible answers *You must join a channel
   before enabling the microphone.*
2. Check that the microphone is on: press Shift-Command-A.
3. If you use push-to-talk, check that you've recorded a key. Until you do, the microphone behaves
   as in always-on mode.
4. If tt-Accessible reports *Microphone access was denied by macOS*, choose Apple menu > System
   Settings, click Privacy & Security, click Microphone, then turn on tt-Accessible.
5. Open Preferences, click Audio, then check the **Input device** and the **Input channels** preset.
   On an audio interface, the microphone is rarely on input 1.
6. If tt-Accessible announces *Transmission blocked by the channel operator*, an operator has taken
   your right to speak there.

To settle it, press Shift-Command-H: if you can hear yourself through the channel, you're on air.

## If everyone hears themselves come back

Your speakers are being picked up by your microphone. Either use headphones, or open Preferences,
click Audio, then set **Microphone processing** to **Echo cancellation + noise reduction**. On
macOS 14.2 and later this also cancels VoiceOver and system sounds.

## If the sound stops after plugging something in

tt-Accessible notices device changes and restarts its audio engine on its own. If something is still
wrong, open Preferences, click Audio, then click **Refresh Devices**. If the microphone stopped,
tt-Accessible says *Microphone stopped after an audio device change. Turn it on again.*

## If recording won't start

The channel was probably created with **No audio recording**, and tt-Accessible announces
*Recording is not allowed in this channel.* Only an account with the right to record voice can
override it. See [Record a conversation](recording.html).

## If streaming an app doesn't work

- Streaming the audio of an app or of VoiceOver requires macOS 13 or later, and browsing apps that
  aren't running requires macOS 14.2 or later.
- If tt-Accessible answers *The selected source has no audio to capture right now*, make sure the
  app is really running and playing something.

See [Stream audio into a channel](streaming.html).

## If the server refuses your password

- Click **Edit Credentials** in the alert to correct your user name or password.
- If the server uses BearWare web login, check that your account is signed in: open Preferences,
  then click BearWare.
- If macOS refuses access to the stored password, open Keychain Access, delete the **ttaccessible**
  entry for that server, then try again.

## If the connection keeps dropping

Open Preferences, click Connection, then select **Adaptive jitter buffer**, which improves audio on
unstable connections. Automatic reconnection and rejoining your last channel are already on in the
same pane.

## Report a problem

1. Choose Help > Contact the Developer.
2. Click the **Type** pop-up menu, then choose **Report a problem**, **Suggestion**, **Question** or
   **Other**.
3. Enter your email address and your message.
4. To make a sound problem diagnosable, select **Attach the audio diagnostic log**. Reproduce the
   problem first, then send the message: the log is cleared every time you open the app.
5. Click Send.

Your app version, macOS version and audio settings are attached to help with troubleshooting. The
log itself is stored in your home folder, in
`Library/Containers/com.math65.ttaccessible/Data/Library/Logs/TTAccessible/audio.log`.

To report something publicly instead, choose Help > Report an Issue.

**See also:** [Set up your audio devices](audio-setup.html) · [Talk in a channel](talking.html)
