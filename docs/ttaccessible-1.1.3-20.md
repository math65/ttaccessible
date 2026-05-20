Auto-Away reliability fix.

## Fixed

- **Auto-Away no longer flips back to Available without input.** Earlier versions used IOKit's `HIDIdleTime`, which silently returns 0 when its system query fails — looking exactly like "the user just typed something" and pulling the user out of Away within seconds of going Away. The detection now uses `CGEventSource.secondsSinceLastEventType` (keyboard + mouse buttons), with a "sharp idle drop" requirement so a single transient reading can't trigger deactivation. Polling tightens to 0.5s while Away so real input restores Available within a second. Thanks to [Casey Reeves (@xogium)](https://github.com/xogium) for the patch ([PR #6](https://github.com/math65/ttaccessible/pull/6)).

## Install

If you're on 1.1.2, ttaccessible will install this update for you — no action needed.

If you're on 1.1.0 or 1.1.1, you still need to install 1.1.2 manually first (see the [v1.1.2 release notes](https://github.com/math65/ttaccessible/releases/tag/v1.1.2)). 1.1.3 will follow automatically after that.

Manual install:

1. Download `ttaccessible-1.1.3-20.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.
