# Localization glossaries

One file per language the app ships, next to its `Localizable.strings` catalogue in
`App/ttaccessible/<code>.lproj/`. Each file records the terms and conventions already
decided for that language, so every new string, whoever drafts it, says things the same
way as the rest of the app.

These files live here, outside `App/ttaccessible`, because everything in that folder is
bundled into the app.

| File | Language | Reviewer |
|------|----------|----------|
| [fr.md](fr.md) | French | Mathieu Martin |
| [tr.md](tr.md) | Turkish | none yet: drafted, not reviewed by a native speaker |
| [ru.md](ru.md) | Russian | Georgy Aliabyev |
| [zh-Hans.md](zh-Hans.md) | Simplified Chinese | draft; user/VoiceOver review pending |

## Adding a string

1. Add the key to **every** catalogue in the same change. A missing key is never
   replaced by the English text: the app shows it, and VoiceOver reads it, as the raw key
   (`history.transmitQueue.position`).
2. The first version of each translation may be drafted with Claude, from this glossary.
3. The reviewer for that language reads it **before the change is merged**, not before
   the release.
4. The reviewer gets a flat list, one string per entry, in this order: the key, the
   English, the draft. Never a diff of `.strings` files, which is hard to read with a
   screen reader. Short strings that stand alone (button titles, accessibility labels
   and hints) are flagged, because a draft goes wrong there most often.

## Entry format

One entry per line, no YAML:

- English term — translation — note, if any
