# uninstall 🗑️

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
   alias uninstall="~/<your_cloned_path>/uninstall-cli.sh"
   ```

3. Usage: In your terminal:

   ```bash
   uninstall /Applications/<name_of_your_app>.app 
   ```

## Usage 💻

```bash
uninstall /Applications/app_name.app
```

By default this runs a dry-run and prompts before making changes.

```bash
uninstall --yes /Applications/app_name.app
uninstall --dry-run /Applications/app_name.app
uninstall --verbose /Applications/app_name.app
```

Flags:

- `--dry-run`: Show matches and summary without removing anything (default).
- `--yes`: Skip confirmation prompts and proceed.
- `--verbose`: Show full running-process command lines.

Behavior:

- Prompts once before changes; after confirmation it attempts to quit/kill app processes and unload matching launch items.
- Uses bundle ID and app-name matches shown in the preflight report for cleanup.

## Release 📦

1. Bump `VERSION` (X.Y.Z) and commit.
2. Push to `main`. The release workflow triggers on changes to `VERSION` and creates tag `vX.Y.Z` plus release assets.
3. Open the Actions logs for the release workflow and copy the "Homebrew tap update details" snippet (job: `release_info`).
4. Update [`Formula/uninstall.rb`](https://github.com/GrantBirki/homebrew-tap/blob/main/Formula/uninstall.rb) in the `homebrew-tap` repo with the new `version`, `url`, and `sha256`, then commit and push.

Triggering a new release is just updating `VERSION` on `main` (or running the workflow manually) since the workflow keys off that file.

---

Inspired by [t18n/uninstall-cli](https://github.com/t18n/uninstall-cli).
