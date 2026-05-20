Bug fix release with two important fixes around quit stability and microphone transmission.

## Fixed

- **Quit crash**: a race condition in the TeamTalk SDK could crash the app on quit when an active session was being torn down. The app now waits briefly for the SDK's internal threads to finish before letting the process exit.
- **Microphone transmission on the system default device**: voice was not being transmitted when the selected microphone was the macOS system default input. The capture engine now uses an explicit Core Audio device binding for every input, including the system default. Thanks to [Casey Reeves (@xogium)](https://github.com/xogium) for the fix.

## Install

1. Download `ttaccessible-1.0.1-15.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.
