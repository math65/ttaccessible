---
title: Set up your audio devices
description: Choose your input and output devices, remove echo and background noise, and test your microphone.
keywords: audio device, input, output, echo cancellation, AEC, noise reduction, preview, channels, headphones
anchor: audio-setup
---

You can choose which devices tt-Accessible uses and how it treats your microphone. Changes take
effect immediately, even during a session.

## Choose your devices

1. Open Preferences, then click Audio in the sidebar.
2. Click the **Output device** pop-up menu, then choose **System default**, a specific device, or
   **No output device** to run tt-Accessible silently.
3. Click the **Input device** pop-up menu, then choose **System default** or a specific microphone.

If you plug in or unplug a device and it doesn't appear, click **Refresh Devices**. tt-Accessible
also notices device changes on its own and restarts its audio engine, so headphones connected during
a session are picked up without action from you.

## Remove echo and background noise

1. Open Preferences, then click Audio.
2. Click the **Microphone processing** pop-up menu, then choose one of the following:
   - **None** — your microphone is sent as it is.
   - **Noise reduction** — removes background noise from your microphone.
   - **Echo cancellation + noise reduction** — also removes the sound of your speakers from what you
     send.

Echo cancellation is what lets you work without headphones: without it, everyone hears themselves
come back through your microphone. On macOS 14.2 and later, tt-Accessible uses the sound your Mac
actually produces as its reference, so VoiceOver and system sounds are cancelled along with the
voices of the channel. On earlier versions, only TeamTalk audio can be cancelled.

## Choose which inputs of your device are used

Click the **Input channels** pop-up menu, then choose **Auto**, a single mono input, a stereo pair,
or a mono mix of two inputs. This matters with audio interfaces, where the microphone is rarely on
input 1.

If you change device and the preset no longer fits, tt-Accessible falls back to Auto and tells you.

## Test your microphone

1. Open Preferences, then click Audio.
2. Click **Audio preview**. Your microphone is played back to you with the processing you selected,
   without being connected to anything.
3. Click **Stop preview** to end the test.

During a session, press Shift-Command-H to hear yourself through the channel instead.

## Keep the levels you set for other people

Click the **Per-user volume memory** buttons, then choose one of the following:

- **Off** — every level returns to 50% when you reconnect.
- **This session only** — levels are forgotten when you quit.
- **Always** — levels are remembered from one launch to the next.

Levels are kept per server, so a level you set on one server never carries over to another.

**See also:** [Talk in a channel](talking.html) · [If something doesn't work](troubleshooting.html)
