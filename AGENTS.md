# AGENTS

This repository contains the `uninstall` CLI for macOS. It is a developer‑friendly alternative to app removal tools, implemented as a single bash script.

This document captures project intent, safety requirements, and operational workflows so future agent sessions keep the tool safe, predictable, and consistent.

## Project Goals

- Provide a "one‑shot delete" workflow: show a preflight report, ask once, then complete the uninstall.
- Be safe by default: avoid deleting unrelated apps or vendor‑wide data.
- Be comprehensive for common macOS artifacts: app bundle, bundle‑ID paths, launch items, caches, logs, etc.
- Maintain a simple, auditable bash script with clear output and a final summary.

## Hard Safety Requirements

These are absolute constraints and must never be violated:

- Never delete files belonging to other apps.
- Never implement vendor‑prefix matching (example: `com.company.*`) or other broad patterns.
- Do not do deep or recursive "wide" scans unless explicitly requested and clearly labeled unsafe.
- Do not add extra confirmation prompts beyond the initial one for the default path (the flow is: preflight -> confirm -> do).

## Default Behavior (No Flags)

- Runs a preflight report and asks once to confirm.
- If confirmed, it:
  - Attempts to quit the app by bundle ID.
  - Kills remaining app processes that are inside the app bundle.
  - Unloads matching LaunchAgents/LaunchDaemons (verified by plist contents).
  - Moves matched paths to Trash via Finder (not hard delete).
- Prints a summary report and a final "Done" on success.

## Matching Strategy (Safety First)

The script intentionally uses strict, low‑risk matching rules.

### Bundle ID Matches (Primary, Safe)
Paths are only included when they directly incorporate the exact bundle ID or related bundle IDs discovered inside the app bundle. Examples:

- `~/Library/Preferences/<bundle_id>.plist`
- `~/Library/Containers/<bundle_id>`
- `~/Library/Application Support/<bundle_id>`
- `~/Library/HTTPStorages/<bundle_id>`
- `~/Library/Saved Application State/<bundle_id>.savedState`
- `~/Library/Logs/<bundle_id>`
- `~/Library/Caches/<bundle_id>`
- `~/Library/Group Containers/group.<bundle_id>`
- `/Library/Preferences/<bundle_id>.plist`
- `/Library/Logs/<bundle_id>`
- `/Library/PrivilegedHelperTools/<bundle_id>`
- User cache/temp directories `getconf DARWIN_USER_CACHE_DIR` and `getconf DARWIN_USER_TEMP_DIR` with `<bundle_id>`

### App Name Matches (Secondary, Review)
App‑name paths are listed separately and are marked "review". These are still included in matched paths but are visually distinguished in the preflight output to encourage review.

The current set includes common locations like `~/Library/Application Support/<AppName>` and `~/Library/Logs/<AppName>`.

### Never Allowed
- Vendor‑prefix matches (example: `com.company.*`)
- Deep recursive "find" on `~/Library` or `/Library` that could match unrelated apps
- Broad substring searches across system paths

## Launch Items (LaunchAgents/LaunchDaemons)

Launch items are only matched when the plist contents explicitly reference:

- The exact app bundle path, or
- The exact bundle ID or related bundle IDs (derived from the app bundle).

Implementation detail:
- The script parses plist content with `/usr/bin/plutil -p` and verifies matches.
- It then unloads via `launchctl bootout` (user or system domain depending on path).
- Only those verified plists are moved to Trash.

If launch items are present, the preflight report states that unloading may prompt for sudo.

## Process Handling

Default behavior after confirmation:

- Attempt to quit the app by bundle ID using AppleScript.
- Only kill processes whose command line lives under `<app_path>/Contents/`.
- This avoids killing unrelated processes with the same name.

Output:
- Default process list is abbreviated (`PID` + command).
- `--verbose` prints full process command lines.

## Output + Colors

- Use color to highlight key information only (headers, warnings, errors, prompts, success).
- Normal informational lines should remain uncolored.
- Summary must appear just before the final "Done".

## Flags

- `--dry-run`: Show matches and summary without removing anything (default).
- `--yes`: Skip confirmation prompts and proceed.
- `--verbose`: Show full running process command lines.

## Release Process

Releases are driven by the `VERSION` file in this repo.

### Trigger

- Update `VERSION` (X.Y.Z) and push to `main`.
- The GitHub Actions release workflow triggers on `VERSION` changes.

### Assets

The workflow creates:

- `uninstall-<version>.tar.gz`
- `uninstall-<version>.tar.gz.sha256`

### Homebrew Tap Update (Required)

After a release, update the tap formula in the separate repo:

Repo: `https://github.com/GrantBirki/homebrew-tap`
File: `Formula/uninstall.rb`

Steps:

1. Open the Actions logs for the release workflow and find the "Homebrew tap update details" snippet (job: `release_info`).
2. Update the formula with:
   - `version`
   - `url` (must be under the release tag)
   - `sha256` (from the workflow output)
3. Commit and push the tap repo.

Important:
- The `version` line must be above the `url` line so `#{version}` is interpolated correctly.
- The formula includes `livecheck` to detect GitHub releases automatically, but installs still require a formula version bump.

## Homebrew Installation/Update

Users install via:

```
brew install grantbirki/tap/uninstall
```

Users update via:

```
brew update
brew upgrade uninstall
```

If updates do not appear, confirm the tap formula version matches the latest release.

## Testing / Verification

- Lint: `bash -n uninstall`
- Manual: `./uninstall /Applications/AppName.app` (dry run + confirmation)
- Manual with full process output: `./uninstall --verbose /Applications/AppName.app`

## Change Guidelines

When modifying `uninstall`:

- Preserve the single confirmation flow.
- Keep safe matching rules; do not add vendor‑prefix or broad substring matching.
- Keep launch item matching strict (plist content must reference app path or bundle IDs).
- Keep output readable; use color for emphasis only.
- Always ensure summary + final "Done" remain at the end.

When modifying releases:

- Only bump `VERSION` when ready to release.
- Ensure the GitHub Actions release workflow remains pinned to action SHAs.
- Ensure the release snippet continues to output correct formula info.
