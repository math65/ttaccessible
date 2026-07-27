---
title: Getting started
description: Install tt-Accessible, choose your language, connect for the first time, and keep the app up to date.
keywords: install, first launch, language, microphone permission, update, Sparkle, beta
anchor: getting-started
---

## What you need

- **macOS 12.0 (Monterey) or later.** The app is a universal binary and runs natively on both Apple
  silicon and Intel Macs.
- **A TeamTalk 5 server** to connect to — either one you were given the details for, or a `.tt` file
  or `tt://` link someone sent you.
- A **microphone** if you want to talk. You can listen without one.

Some features need a more recent system: echo cancellation captures the whole system output on
macOS 14.2 and later, and streaming the audio of an application or of VoiceOver also requires a
recent macOS (see [Streaming media](streaming.html)).

## Installing

1. Download the latest release archive from the project's releases page.
2. Unarchive it, then drag **tt-Accessible** into your Applications folder.
3. Open it. The first launch may take a moment while macOS checks the app.

## First launch

The app asks **Choose Your Language** — English or French. You can change this later in
[Preferences → General](preferences.html#prefs-general); the app must be restarted for the change to
apply everywhere.

The first time you turn the microphone on, macOS asks for permission to use it. If you refuse, the
app reports *Microphone access was denied by macOS.* and you have to grant access in System
Settings → Privacy & Security → Microphone.

## Connecting for the first time

The window that opens at launch is **TeamTalk Servers**. It is empty until you add a server:

- Press **Command-N** to fill in the details by hand, or
- Choose **Server → Import TeamTalk Servers…** (Shift-Command-I) if you have a configuration file, a
  `.tt` file or a `tt://` link.

Then select the server in the list and press **Return** or **F2**.

[Servers](servers.html) covers all of this in detail.

## Keeping the app up to date

tt-Accessible checks for updates on its own and offers to install them.

- **tt-Accessible → Check for Updates…** checks immediately.
- [Preferences → General](preferences.html#prefs-general), section **Updates**, has
  **Check for updates automatically** (on by default) and **Include beta versions** (off by
  default). Beta versions may contain bugs; turn the option off to receive only stable releases.

## Getting help

The **Help** menu also offers **View Project on GitHub**, **Report an Issue…** and, when the build
includes it, **Contact the Developer…** — a form that sends a message straight to the developer,
optionally with the audio diagnostic log attached. See [Troubleshooting](troubleshooting.html).
