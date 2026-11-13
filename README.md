# uninstall 🗑️

[![test](https://github.com/GrantBirki/uninstall/actions/workflows/test.yml/badge.svg)](https://github.com/GrantBirki/uninstall/actions/workflows/test.yml)

CLI tool for macOS to uninstall an app from your system

This script is an open-sourced alternative for [App Cleaner](https://freemacsoft.net/appcleaner/) on Mac OS

## Installation

Install via [homebrew](https://brew.sh/):

```bash
brew install grantbirki/tap/uninstall
```

> Tap can be found in [my homebrew-tap](https://github.com/grantbirki/homebrew-tap) repo:

## Updating (Homebrew)

To pick up a new release after it lands in the tap:

```bash
brew update
brew upgrade uninstall
```

If it doesn't upgrade, check that the tap formula version matches the latest release:

```bash
brew info uninstall
```

## Manual Install

1. Clone the repo into your computer. Put it somewhere static.
2. Create an alias in your shell by adding this line

   ```bash
   alias uninstall="~/<your_cloned_path>/uninstall"
   ```

3. Usage: In your terminal:

   ```bash
   uninstall raycast
   ```

## Usage 💻

```bash
uninstall
uninstall --list
uninstall raycast
uninstall "Visual Studio Code"
uninstall /Applications/app_name.app
```

With no arguments, `uninstall` prints the same installed-application list as `uninstall --list`. The list contains one absolute path per line and a total so a path can be copied directly into an uninstall command.

Application discovery searches direct children and one nested directory level under `/Applications` and `~/Applications`. It includes only `.app` directories or symlinks containing `Contents/Info.plist`. It does not search protected applications under `/System/Applications`.

A target containing `/` is treated as an explicit bundle path and must exist. A target without `/` is matched case-insensitively against discovered bundle names, with an optional trailing `.app` ignored. An exact name wins; otherwise one unique literal substring match is accepted. Multiple matches are listed without making changes, and the command must be rerun with a full path.

After a target resolves uniquely, the normal preflight runs. By default, the command asks once before making changes.

```bash
uninstall --dry-run raycast
uninstall --verbose raycast
uninstall --yes /Applications/Raycast.app
uninstall --bundle-id com.example.App
```

Flags:

- `--list`: List installed applications. It cannot be combined with an application or uninstall flags.
- `--bundle-id <id>`: Clean up exact bundle ID matches when the app bundle is already gone. It cannot be combined with an app target or `--list`.
- `--dry-run`: Show matches and summary without removing anything (default).
- `--yes`: Skip confirmation prompts and proceed.
- `--verbose`: Show full running-process command lines.

Behavior:

- Prompts once before changes; after confirmation it attempts to quit/kill app processes and unload matching launch items.
- Uses bundle ID and app-name matches shown in the preflight report for cleanup.
- Moves the app bundle last and keeps it in place if any data cannot be moved, so the same command can be retried.
- Shows Finder's error when a move to Trash fails and returns a nonzero exit status.

## Retrying cleanup

If cleanup fails, resolve the reported Finder error and rerun the same command. The app bundle stays available until its data has moved successfully.

If the app was already removed, use its exact bundle ID:

```bash
uninstall --dry-run --bundle-id com.example.App
uninstall --bundle-id com.example.App
```

This mode keeps the normal preflight and single confirmation. It searches the existing bundle ID locations and matching launch items, without guessing an app name, discovering helper IDs, or stopping processes. If a helper has a separate bundle ID, review and clean it up separately.

Run `uninstall` as your normal user. The CLI requests sudo for privileged process or launch-item operations when needed. Finder Automation and macOS privacy permissions are separate from administrator access; running the whole command with sudo does not grant those permissions. Check the reported error and the relevant Privacy & Security setting before retrying. See [Apple's file-access guidance](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web).

## Release 📦

1. Bump `VERSION` (X.Y.Z) and commit.
2. Push to `main`. The release workflow runs the repository-owned tests, triggers on changes to `VERSION`, and creates tag `vX.Y.Z` plus release assets with the GitHub CLI installed on the hosted runner.
3. Open the Actions logs for the release workflow and copy the "Homebrew tap update details" snippet (job: `release_info`).
4. After the tap's required 14-day cooldown, update [`Formula/uninstall.rb`](https://github.com/GrantBirki/homebrew-tap/blob/main/Formula/uninstall.rb) in the `homebrew-tap` repo with the new `version`, `url`, and `sha256`, then update its provenance record.

Triggering a new release is just updating `VERSION` on `main` (or running the workflow manually) since the workflow keys off that file.

---

Inspired by [t18n/uninstall-cli](https://github.com/t18n/uninstall-cli).
