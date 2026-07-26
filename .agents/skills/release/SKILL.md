---
name: release
description: End-to-end ttaccessible release — drafts the release notes (English RELEASE_NOTES.md + French RELEASE_NOTES.fr.md + optional AppleVis post) AND builds, signs, notarizes, staples, and publishes via `./build.sh --release` plus the Sparkle appcast. Handles both stable releases and beta-channel releases (`./build.sh --release --beta`). Use this whenever the user is cutting a release, says "ship it", "publish the new version", "release vX.Y.Z", "ship a beta", "publish to the beta channel", "what changed since vX and release it", or wants to go from "code is on main" to "users get the update". User-triggered only — the publish half has irreversible side effects (binary publication, GitHub release, appcast push), so it never runs automatically.
disable-model-invocation: true
---

# Release ttaccessible (notes → publish)

One skill, two phases. Phase A (notes) is safe — it only writes Markdown. Phase B
(publish) is destructive and irreversible — it builds, notarizes, and pushes a
public release. **Never run Phase B without an explicit go-ahead from the user.**

**Scope control via arguments:**
- Invoked with `notes` (e.g. `/release notes`) → run **Phase A only**, then stop.
- Invoked with `publish` or no argument → run Phase A, then **pause and confirm**
  before Phase B (**stable** channel — reaches every user).
- Invoked with `beta` (e.g. `/release beta`, `/release publish beta`) → run Phase A,
  then **pause and confirm** before Phase B, publishing to the **beta** channel
  via `./build.sh --release --beta` (see "Beta releases" below). Only users who
  enabled "Include beta versions" in Preferences > General receive it.

Do not rely on session memory for what shipped — always query git.

---

## Phase A — Draft the release notes

### A1. Identify the prior tag

```bash
git tag --sort=-v:refname | head -5
```

Pick the most recent published tag (e.g. `v1.4.0`). The new release is the next semver.

### A2. Scan commits since the prior tag

```bash
git log <prev-tag>..HEAD --oneline --no-merges
```

Group commits into themes: fixes, accessibility, audio, UX, release plumbing. Skip
pure release-prep commits ("Bump to X", "Update appcast") in user-facing notes.

### A3. Check open PRs

```bash
gh pr list --state open --json number,title,headRefName,author
```

If a PR addresses something you're about to claim as fixed, flag it — the
contributor may have a competing approach. Don't auto-claim it as your fix.

### A4. Write the English notes (`RELEASE_NOTES.md`)

`RELEASE_NOTES.md` and the GitHub release body are always English, not French. Structure:

```markdown
## v<X.Y.Z> (build <N>) — <YYYY-MM-DD>

### Highlights
- One-sentence headline of the most impactful change.

### Fixes
- Bullet per fix, prefixed with the area (Audio, Chat, VoiceOver, etc.).

### Other changes
- Smaller polish items.

### Download
[ttaccessible-<X.Y.Z>.zip](https://github.com/math65/ttaccessible/releases/download/v<X.Y.Z>/ttaccessible-<X.Y.Z>.zip)
```

Always include the **direct asset URL**, not just the release page link.

#### Tone & wording — write for the user, not the commit log

Release notes are read by VoiceOver users deciding whether to update, not by
engineers. Translate each change into the symptom the user felt and what is
different now. Keep it natural and plain.

- **Lead with the user-visible effect**, not the mechanism. "Switching audio
  devices works again" — not "fixed the suppression-window early return".
- **Cut internal jargon.** No CoreAudio/AUHAL/AEC-tap/snapshot/churn/
  suppression-window/route-change vocabulary, no class or function names, no
  file paths. If a term names something the user can't see or act on, drop it
  or replace it with a plain phrase ("echo cancellation starting up", not
  "the AEC tap teardown").
- **Avoid literal translations of code-speak.** "device-list churn" →
  "routine changes in the audio device list"; "no-op" → "had no effect".
- **One symptom per bullet**, bolded lead clause, then a plain-language
  explanation of before → after. Don't merge unrelated fixes into one bullet.
- **Read it aloud test**: if a sentence sounds like a changelog entry or a
  PR title, rewrite it as something you'd say to a non-technical friend.
- The French file follows the same tone — natural French, not a word-for-word calque.

### A5. Write the French notes (`RELEASE_NOTES.fr.md`)

Sparkle shows localized release notes during updates: `build.sh` renders
`RELEASE_NOTES.fr.md` to `docs/<basename>.fr.html`, and `generate_appcast` emits a
`<sparkle:releaseNotesLink xml:lang="fr">` automatically. French users see the
French notes; everyone else falls back to the English `.html`.

- **Write `RELEASE_NOTES.fr.md` from scratch in idiomatic French — do NOT translate
  the English clause-by-clause.** Re-express each change the way a French native
  would phrase it. A word-for-word calque reads as jarring translationese when
  VoiceOver speaks it aloud, and Mathieu *will* reject it ("c'est tout sauf
  naturel"). Read each sentence aloud: if it sounds like translated English,
  rewrite it.
  - Calques that have been rejected before: "une passe ciblée" (a focused pass) →
    "entièrement consacrée à…"; "contribuée par" (contributed by) → "grâce à la
    contribution de…"; "nom attaché" (run-together name) → "écrit d'un seul
    tenant"; "interrupteurs par son" (per-sound switches) → "la liste des sons".
  - Lead with the user-visible effect, same tone rules as the English (A4).
- Use **vouvoiement** ("vous", never "tu") — same rule as app-shipped French strings.
- Keep the structure and the same `.zip` filename in the Download section.
- This file is **only** for the in-app Sparkle dialog. The GitHub release body and
  AppleVis post stay English — do not publish the French version there.
- If you skip `RELEASE_NOTES.fr.md`, the build still works: Sparkle just shows
  English to everyone (the unsuffixed `.html` fallback).

### A6. Commit-issue linkage

- For commits already merged to `main` before the release: reference issues with `Refs #N`.
- For PRs or post-release confirmation: use `Fixes #N` / `Closes #N` so GitHub auto-closes.
- Push early, close issues late.

**If invoked with `notes`: stop here.** Otherwise continue to Phase B.

---

## Phase B — Build & publish (destructive — confirm first)

Before running anything in this phase, summarize what will happen (version, what's
in the notes) and get an explicit go-ahead. These steps sign, notarize, and push a
public release that reaches every user via the in-app updater.

### B0. Prerequisites

- **Version bump committed**: update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
  in `App/ttaccessible.xcodeproj/project.pbxproj`. (Do this now if not already done.)
- `RELEASE_NOTES.md` updated (Phase A).
- Notarytool keychain profile `ttaccessible-notary` is stored.
- On `main`, working tree clean.

### B1. Build, sign, notarize, publish

```bash
./build.sh --release
```

This:
- Builds Release with Xcode.
- Re-signs with `Developer ID Application`.
- Notarizes via the `ttaccessible-notary` profile.
- Staples the ticket.
- Zips the artifact to `BuildArtifacts/`.
- Stages the zip + HTML notes + `appcast.xml` to the appcast staging dir.
- Pushes a draft GitHub release.

Note: `build.sh --release` publishes the GitHub release **live** and pushes the
appcast itself — it does not leave a draft despite older docs.

If you only need to fix release notes **after** publish (no binary change): re-render
the HTML and run `gh release edit` — no rebuild or re-notarize required.

#### Beta releases (`./build.sh --release --beta`)

For a beta-channel release, run:

```bash
./build.sh --release --beta
```

What `--beta` changes versus a stable release:
- `generate_appcast` is passed `--channel beta`, so **only the new appcast item**
  is tagged `<sparkle:channel>beta</sparkle:channel>`. Existing stable entries are
  preserved untouched. The app's `allowedChannels(for:)` (`AppDelegate.swift`)
  returns `["beta"]` only when the user enabled "Include beta versions"
  (Preferences > General), so stable users never see the beta build.
- The GitHub release is created with `--prerelease`.

**Versioning caveat — avoid tag collisions.** The GitHub tag is `v${VERSION}` where
`VERSION` = `CFBundleShortVersionString`. If a beta and the eventual stable share
the same marketing version (e.g. both `1.7.0`), the tag `v1.7.0` collides and the
second run uploads the asset onto the first release instead of creating a new one.
Give betas a distinct `MARKETING_VERSION` such as `1.7.0-beta.1` (bump
`CURRENT_PROJECT_VERSION`/build for every beta — Sparkle compares by build number).
The stable release then uses `1.7.0`. Confirm the intended version with the user.

**No beta channel has been published before** as of the BearWare web-login work, so
expect essentially zero users on the beta channel initially — the announcement must
tell testers to enable "Include beta versions" first, and you'll likely need to
enable it yourself to receive your own beta.

### B2. Commit and push the appcast

The appcast/HTML in `docs/` is served by GitHub Pages. Push the updated files to
`main` so Sparkle clients pick up the update (if `build.sh` hasn't already).

### B3. Verify

- Direct asset URL resolves:
  `https://github.com/math65/ttaccessible/releases/download/v<X.Y.Z>/ttaccessible-<X.Y.Z>.zip`
- Appcast XML loads at the GitHub Pages URL and lists the new version.
- Spot-check the in-app updater on a previous-version install.

### B4. Announce (optional, AppleVis)

If announcing on AppleVis, the post uses different formatting rules:

- Subject line: 64 characters max.
- Headings: H4 or lower only (H1–H3 are reserved).
- Body is Markdown.
- Include a clickable direct asset URL, not just the release page.

Draft the AppleVis version separately — do not reuse the GitHub body verbatim.

After publishing, close any issues fixed by this release with a short note pointing
at the new version.
