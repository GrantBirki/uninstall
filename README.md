# uninstall

CLI tool for macOS to uninstall an app from your system

This script is an open-sourced alternative for [App Cleaner](https://freemacsoft.net/appcleaner/) on Mac OS

## Installation

Install via [homebrew](https://brew.sh/):

```bash
brew install grantbirki/tap/uninstall
```

> Tap can be found in [my homebrew-tap](https://github.com/grantbirki/homebrew-tap) repo:

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

## Usage

```bash
uninstall /Applications/app_name.app
```

By default this runs a dry-run and prompts before making changes.

```bash
uninstall --yes /Applications/app_name.app
uninstall --dry-run /Applications/app_name.app
```
