---
title: Stream audio into a channel
description: Send a file, an internet radio, an audio device, another app or VoiceOver into the channel alongside your voice.
keywords: streaming, media file, URL, radio, device, application, VoiceOver, media player, broadcast volume
anchor: streaming
---

You can send audio into the channel at the same time as your voice — a music file, an internet
radio, the sound of another app, or VoiceOver itself, so the channel hears what your screen reader
is saying. All four commands are in the Shortcuts menu.

## Stream a file

1. Choose Shortcuts > Stream Media File, or press Option-Command-S.
2. Select an audio or video file, then click Stream.

Video support depends on what TeamTalk can open on your Mac, and 10-bit video isn't supported. When
a file carries video, the Video panel of the main window shows it.

## Stream an internet radio or another URL

1. Choose Shortcuts > Stream URL, or press Option-Command-U.
2. Enter the address of the stream, then click Stream. You can use the `http`, `https`, `rtmp`,
   `rtmps`, `rtsp` and `mms` schemes.

## Stream a device, apps or VoiceOver

1. Choose Shortcuts > Stream Audio from This Mac, or press Option-Command-A.
2. In the **Audio source** list, tick what you want to send. Use the arrow keys to move through the
   list and the Space bar to tick or untick.
3. Select **Play the streamed audio back to me** if you want to hear what you're sending. It's off,
   so you aren't forced to listen to it.
4. Select **Mute this source on this Mac while streaming** to silence the source for yourself while
   the channel keeps hearing it. It only applies to applications, on recent versions of macOS.
5. Click Stream.

### What you can tick

- **Several applications at once.** Your music player and VoiceOver, say, so the channel hears both
  what you're listening to and what your screen reader is saying.
- **All audio from this Mac**, when naming the apps one by one isn't worth it. tt-Accessible's own
  output is left out of the capture, otherwise the channel would hear itself come back. Be aware
  that notifications and system sounds go out too.
- **An input device**, which streams on its own: ticking a device unticks the applications, and the
  other way round. tt-Accessible announces whatever was just unticked.

To pick an app that isn't running, click **Select Application** — this requires macOS 14.2 or later.
Streaming the audio of an app, of VoiceOver or of the whole Mac requires macOS 13 or later.

The stream keeps going even while the source is silent, so a pause in the music doesn't end it. Your
last choice is ticked again next time, even when it covered several applications.

If the app you picked isn't producing any sound, tt-Accessible answers *The selected source has no
audio to capture right now.*

## Control a running broadcast

While a stream is running, the main window shows a block of controls under the sound sliders: the
name of what's going out, a button to interrupt it, a Stop button and the broadcast volume. A media
file adds a Position slider; a radio, a device or an app has none, because their broadcast has no
end to reach.

These keys work as soon as the focus is inside that block:

| Key | Media file | Radio, device or app |
|---|---|---|
| Space | Pause or resume | Mute or unmute |
| Escape | Stop | Stop |
| Left Arrow or Right Arrow | Skip 5 seconds back or forward | No effect |
| Up Arrow or Down Arrow | Change the broadcast volume | Change the broadcast volume |

Option-Command-M does the same thing from anywhere in the app.

A device, an app and VoiceOver never pause: the source is muted, but the broadcast keeps running.
The channel still sees you streaming and hears nothing, until you unmute.

The broadcast volume sets how loud the stream is sent to the channel, independently of the level you
listen at. At 0%, nothing goes out.

## Stop streaming

Choose Shortcuts > Stop Streaming, or press Option-Command-Period. tt-Accessible announces
*Streaming finished*, and both the start and the end appear in the session history.

Everyone subscribed to your media file stream hears it. Each person can silence it without silencing
your voice — see [Adjust what you hear from each person](users.html).

**See also:** [Talk in a channel](talking.html) · [Record a conversation](recording.html)
