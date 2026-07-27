---
title: Streaming media
description: Play a file, an internet stream, an audio device, another app or VoiceOver into the channel.
keywords: streaming, media file, URL, radio, device, application, VoiceOver, media player, broadcast volume
anchor: streaming
---

tt-Accessible can send audio into the channel alongside your voice — a music file, an internet
radio, the output of another application, or even VoiceOver itself so that the channel hears what
your screen reader is saying.

All four commands live in the **Shortcuts** menu.

## Streaming a file

**Option-Command-S** — *Stream Media File…* — opens a file picker. Video support depends on what
TeamTalk can open on your Mac; 10-bit video is not supported. When a file carries video, the
collapsible **Video** panel of the main window shows it.

## Streaming a URL

**Option-Command-U** — *Stream URL…* — asks for the address of an audio stream, such as an internet
radio. The `http`, `https`, `rtmp`, `rtmps`, `rtsp` and `mms` schemes are accepted.

## Streaming a device, an application or VoiceOver

**Option-Command-A** — *Stream a Device or Application…* — opens a sheet with:

- **Audio source** — an audio input of your Mac, **VoiceOver**, or an entry under **Applications**.
  **Select Application…** lets you browse any installed app, even one that is not running, on macOS
  14.2 and later. Streaming an application's or VoiceOver's audio requires macOS 13 or later.
- **Play the streamed audio back to me** — off by default, so you are not forced to listen to what
  you are broadcasting.
- **Mute this source on this Mac while streaming** — silences the source locally while the channel
  keeps hearing it. Available on recent systems, and only for an application source.

The stream keeps going even while the source is silent, so a pause in the music does not end the
broadcast. Your last choice is preselected the next time.

If the app you picked is not producing any audio, the app answers *The selected source has no audio
to capture right now.*

## The media player

While a stream is running, the **Media Player** window shows *Playing:* followed by the source, and
gives you:

| Key | Action |
|---|---|
| Space | Play or pause |
| Escape | Stop |
| Left / Right arrow | Seek 5 seconds back or forward |
| Up / Down arrow | Broadcast volume |

**Broadcast volume** sets how loud the stream is sent to the channel, independently of your own
listening level.

## Stopping

**Option-Command-.** (Option-Command-period) — *Stop Streaming* — ends the stream. The app announces
*Streaming finished*, and both the start and the end are recorded in the session history.

## What others hear

The stream reaches everyone subscribed to your **Media File** stream. Anyone can silence it on their
side without silencing your voice, with *Mute media stream locally* — see
[People you hear](users.html).
