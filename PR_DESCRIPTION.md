# Pull Request Summary

## Summary

- Expands TeamTalk import flows:
  - Adds an import source picker for TeamTalk configuration files, `.tt` files, and pasted `tt://` links.
  - Adds `.tt` file import with duplicate detection and replacement.
  - Adds pasted `tt://` link parsing and import into the saved-server editor.
  - Preserves imported `.tt` server names, auth info, join channel, and channel password.
  - Prompts to save temporary `.tt` or `tt://` connections before disconnecting or quitting.

- Adds server export flows:
  - Adds Export Server menu support for saved and connected servers.
  - Supports exporting a `.tt` file or copying a `tt://` link.
  - For connected servers, optionally includes the current channel path and channel password.

- Adds account-specific export actions:
  - Adds right-click actions in User Accounts for exporting a `.tt` file, copying a `tt://` link, and deleting the account.
  - Adds VoiceOver custom actions and `VO+Shift+M` menu support for the same account actions.

- Improves sound pack support:
  - Adds custom sound pack import from a selected folder, deletion, folder reveal, and per-sound replacement/reset.
  - Uses the chosen folder name as the sound pack name.
  - Adds a Required Files dialog showing required `.wav` filenames and what each sound is for.
  - Standardizes custom sound filenames through `NotificationSound.soundPackFileName`.

- Improves user audio controls:
  - Adds media-file mute/unmute alongside voice mute.
  - Adds separate voice and media-file volume controls.
  - Stores media-file volume preferences per username.
  - Changes gain sliders to display/use 0-100% while mapping internally to dB.
  - Keeps slider accessibility values numeric and exposes formatted text through value descriptions to avoid VoiceOver slider jumps.

- Improves file transfer behavior:
  - Tracks upload/download/delete command completion.
  - Keeps security-scoped file URLs alive during transfers.
  - Announces transfers when TeamTalk reports them active.
  - Handles upload quota checks and refreshes channel files after relevant transfer events.

- Keeps user/account state fresher:
  - Caches and publishes account-list updates after create/update/delete.
  - Refreshes current session identity/permissions when the current account changes.

## Verification

- Built successfully with:

```sh
xcodebuild -project App/ttaccessible.xcodeproj -scheme ttaccessible -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Notes

- Existing warnings remain around `AppDelegate` actor isolation and WebRTC object files built for a newer macOS version.
