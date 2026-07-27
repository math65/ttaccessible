---
title: The channel mixer
description: Balance a whole channel by ear — per-user volume, pan, mute and solo, driven entirely from the keyboard.
keywords: mixer, channel strip, volume, pan, mute, solo, keyboard, VoiceOver
anchor: mixer
---

The channel mixer turns the people in your channel into a small mixing desk: one **channel strip**
per person, each with its own level, stereo position, mute and solo. Because the app builds the mix
itself, you can place one person on the left and another on the right, or bring back someone who is
too quiet, without touching anyone else.

**Command-5** moves the cursor into the mixer. When you are alone it simply says *No other users in
this channel.*

## What a strip contains

| Control | Range |
|---|---|
| Volume | 0 to 100%, in steps of 2 |
| Pan | Left to right, centre by default |
| Media volume | The level of the media file that person streams |
| Media pan | The stereo position of that stream |
| Mute | Silences both the voice and the media of that person |
| Solo | Silences everyone who is not soloed |

Each strip is named after the person, followed by their level and by *muted* when it applies, so
moving from strip to strip already tells you the state of the channel.

## Keyboard control

While the cursor is in the mixer, single keys drive it directly. They are ignored while you are
typing in a text field, so the chat is never affected.

| Key | Effect |
|---|---|
| Up / Down arrow | Voice volume of the focused person |
| Left / Right arrow | Voice pan |
| Command-Up / Command-Down | Media volume — or the master volume when no strip is focused |
| Command-Left / Command-Right | Media pan |
| V | Speaks the volume; press twice to reset it to 50% |
| P | Speaks the pan; press twice to re-centre it |
| M | Speaks the mute state; press twice to toggle it |
| S | Speaks the solo state; press twice to toggle it |
| Command-P | Speaks the media pan; press twice to re-centre it |

The two presses must follow each other quickly. Holding an arrow repeats it, slowly at first and
then faster, so a long move stays controllable.

Every action is spoken immediately, which means you can balance a channel entirely by ear without
ever reading the screen.

## Where the values are kept

Mixer levels are the same per-user levels as the ones in *Adjust volume…* (see
[People you hear](users.html)). Whether they survive a reconnection or a relaunch depends on
*Per-user volume memory* in [Preferences → Audio](preferences.html#prefs-audio).
