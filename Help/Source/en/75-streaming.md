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

## Stream a device, an app or VoiceOver

1. Choose Shortcuts > Stream a Device or Application, or press Option-Command-A.
2. Click the **Audio source** pop-up menu, then choose an audio input of your Mac, **VoiceOver**, or
   an app under Applications. To pick an app that isn't running, choose **Select Application** — this
   requires macOS 14.2 or later. Streaming the audio of an app or of VoiceOver requires macOS 13 or
   later.
3. Select **Play the streamed audio back to me** if you want to hear what you're sending. It's off,
   so you aren't forced to listen to it.
4. Select **Mute this source on this Mac while streaming** to silence the source for yourself while
   the channel keeps hearing it. This option appears for apps on recent versions of macOS.
5. Click Stream.

The stream keeps going even while the source is silent, so a pause in the music doesn't end it. Your
last choice is selected again next time.

If the app you picked isn't producing any sound, tt-Accessible answers *The selected source has no
audio to capture right now.*

## Control what's playing

While a stream is running, the Media Player window shows what's playing and offers these keys:

| Key | Action |
|---|---|
| Space | Play or pause |
| Escape | Stop |
| Left Arrow or Right Arrow | Skip 5 seconds back or forward |
| Up Arrow or Down Arrow | Change the broadcast volume |

The broadcast volume sets how loud the stream is sent to the channel, independently of the level you
listen at.

## Stop streaming

Choose Shortcuts > Stop Streaming, or press Option-Command-Period. tt-Accessible announces
*Streaming finished*, and both the start and the end appear in the session history.

Everyone subscribed to your media file stream hears it. Each person can silence it without silencing
your voice — see [Adjust what you hear from each person](users.html).

**See also:** [Talk in a channel](talking.html) · [Record a conversation](recording.html)
