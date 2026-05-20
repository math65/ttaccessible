Major infrastructure release: ttaccessible now uses [Sparkle](https://sparkle-project.org) for automatic updates.

## What changed

- **Updates install themselves.** When a new version is available, you'll see Sparkle's native window with the release notes. Click **Install Update**, the app quits, swaps itself out, and relaunches on the new version. No more downloading a zip and dragging the app to /Applications manually.
- **Beta channel.** Preferences → General now has an *Include beta versions* toggle. Off by default — leave it off if you only want stable releases.
- **Auto-check toggle.** Same section has a *Check for updates automatically* toggle. On by default; checks once every 24 hours.

## Migration

This is the last release where the old in-app updater offers the new version. From 1.1.0 onward, Sparkle handles everything automatically.

If you're on 1.0.2 or earlier, the old updater will tell you 1.1.0 is available and ask you to download it manually one final time. After that, you're on Sparkle.

## Install

1. Download `ttaccessible-1.1.0-17.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.
