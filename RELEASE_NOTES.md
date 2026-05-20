Bug fix release restoring the keyboard shortcut for streaming an audio file.

## Fixed

- **Stream Audio File keyboard shortcut**: ⌥⌘S no longer triggered streaming a file after 1.0.1's Stream submenu refactor — and ⌥⌘U / ⌥⌘. were affected too. SwiftUI does not register `keyboardShortcut` accelerators on items nested inside a `Menu(...)` within a `CommandMenu`. The three Stream items are now back at the top level of the Shortcuts menu, so all three accelerators work and appear next to their menu items. Thanks to the AppleVis forum reporter.

## Install

1. Download `ttaccessible-1.0.2-16.zip` below.
2. Unzip and drag `ttaccessible.app` into your `/Applications` folder, replacing the previous version.
3. Double-click — no Gatekeeper warning thanks to notarization.
