First official release, signed with Developer ID and notarized by Apple. The app leaves beta: no more Gatekeeper warning at install.

## What's new

- **Guided reconnection**: if the server rejects your password or username, a dialog lets you edit your credentials and automatically retries the connection once they're fixed.
- **Stream submenu**: new option to stream a local audio file or a remote URL into the current channel.
- **Update checker**: the app now detects new versions on GitHub and offers to download them.
- **Custom app icon**.

## Under the hood

- First build with hardened runtime enabled and Developer ID signature.
- Reworked password storage (simplified login keychain, more robust).

## Install

1. Download `ttaccessible-1.0.0-13.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder.
3. On first launch, double-click the app — no Gatekeeper warning thanks to notarization.
