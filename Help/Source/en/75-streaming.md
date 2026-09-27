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

The last address you streamed is offered straight away: press Return to start it again as it is.
Earlier addresses are on the Down arrow, and typing the first few characters of one completes it.
The last ten addresses are kept.

## Stream a device, apps or VoiceOver

1. Choose Shortcuts > Stream Audio from This Mac, or press Option-Command-A.
2. Check what you want to send in the list of sources. It opens on what you streamed last time,
   and a group that holds something checked starts open, so nothing you've checked is out of
   reach. The first time, nothing is checked: nothing streams until you choose it.
   **All audio from this Mac** is at the top, then three groups you open and close with the Right
   and Left Arrow keys: **Recently used**, which starts open, **Devices**, and **Applications**,
   which starts with **VoiceOver**. Press Space to check or uncheck the line you're on; with
   VoiceOver, VO-Space does the same. To find a source quickly, type part of its name in the
   **Search sources** field to the left of the list: the list keeps only the matches, opens every
   group that has one and says how many there are. Press Down Arrow to go from the search field to
   the first match.
3. Select **Play the streamed audio back to me** if you want to hear what you're sending. It's off,
   so you aren't forced to listen to it.
4. Select **Mute this source on this Mac while streaming** to silence the source for yourself while
   the channel keeps hearing it. It only applies to applications, on recent versions of macOS.
5. Click Stream.

### What you can check

- **Any combination of devices and applications.** A microphone and your music player, two audio
  interfaces, VoiceOver and an app: everything you check is mixed into one stream. Each device runs
  on its own clock; tt-Accessible keeps them in step, so a long stream doesn't drift apart. When
  loud sources add up to more than the stream can carry, the peaks are eased down instead of
  distorting.
- **All audio from this Mac**, when naming the apps one by one isn't worth it. It goes with devices,
  but not with applications, which it already contains: checking it unchecks the applications, and
  checking an application unchecks it. tt-Accessible announces whatever was just unchecked. Its own
  output is left out of the capture, otherwise the channel would hear itself come back. Be aware
  that notifications and system sounds go out too.

To pick an app that isn't running, click **Select Application…**, next to the list — this requires
macOS 14.2 or later. The app is added to the Applications group, checked.
Streaming the audio of an app, of VoiceOver or of the whole Mac requires macOS 13 or later.

The stream keeps going even while the source is silent, so a pause in the music doesn't end it. Your
last choice is checked again next time, even when it covered several applications. **Recently used**
keeps the last five sources you streamed, newest first; a source that isn't available any more, such
as an unplugged device, is left out.

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

Press Option-Command-A again, or choose Shortcuts > Stop Streaming: while a stream is running,
Stream Audio from This Mac becomes Stop Streaming, and it stops a file or an address just the same.
tt-Accessible announces
*Streaming finished*, and both the start and the end appear in the session history.

Everyone subscribed to your media file stream hears it. Each person can silence it without silencing
your voice — see [Adjust what you hear from each person](users.html).

**See also:** [Talk in a channel](talking.html) · [Record a conversation](recording.html)
