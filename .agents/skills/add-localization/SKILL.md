---
name: add-localization
description: Add or update a localized string in ttaccessible. Use this skill whenever the user introduces any user-facing text — button title, menu item, alert message, accessibility label, VoiceOver announcement, tooltip, error string, dialog body, preferences label — or mentions Localizable.strings, L10n.text, L10n.format, fr.lproj, en.lproj, or asks for a French translation. Trigger even when the user just says "add a button labeled Save" or "show an error when X fails", because that text must land in both en.lproj and fr.lproj simultaneously, and the French version must use vouvoiement ("vous", never "tu").
---

# Add a localized string

ttaccessible ships in English and French. Every user-facing string lives in both files.

## Files

- `App/ttaccessible/en.lproj/Localizable.strings`
- `App/ttaccessible/fr.lproj/Localizable.strings`

## Steps

1. Pick a key in snake_case, scoped by area: `audio.preview.start`, `preferences.connection.skip_kick.label`.
2. Add the entry to **both** `.strings` files. Never add to one without the other.
3. French translation uses **vouvoiement** ("vous", never "tu"). This is non-negotiable for shipped strings.
4. Use in Swift:
   ```swift
   L10n.text("audio.preview.start")
   L10n.format("audio.preview.error_with_device", deviceName)
   ```
5. For pluralization or argument substitution, use `L10n.format` with `%@`, `%d`, `%lld` etc. — match the argument positions across both languages with `%1$@`, `%2$@` if order differs.

## Quick check

After adding, grep both files for the key to confirm parity:

```bash
grep -E '^"<your.key>"' App/ttaccessible/en.lproj/Localizable.strings App/ttaccessible/fr.lproj/Localizable.strings
```

If the key appears in zero or one file, fix it before moving on.
