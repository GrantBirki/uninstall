#!/bin/bash

set -e

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$ROOT_DIR/test/ci_policy_test.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

# shellcheck source=../uninstall
source "$ROOT_DIR/uninstall"

OFF=""
RED=""
GREEN=""
BLUE=""
PURPLE=""

APPLICATIONS_DIR="$TEST_ROOT/Applications"
USER_APPLICATIONS_DIR="$TEST_ROOT/User Applications"
APPLICATION_ROOTS=("$APPLICATIONS_DIR" "$USER_APPLICATIONS_DIR")
export HOME="$TEST_ROOT/Home"

mkdir -p "$APPLICATIONS_DIR/Utilities" "$USER_APPLICATIONS_DIR" "$HOME"

make_app() {
  mkdir -p "$1/Contents"
  touch "$1/Contents/Info.plist"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

assert_equal() {
  local expected actual message
  expected="$1"
  actual="$2"
  message="$3"
  [ "$expected" = "$actual" ] || fail "$message (expected: $expected, actual: $actual)"
}

assert_contains() {
  local output expected message
  output="$1"
  expected="$2"
  message="$3"
  case "$output" in
    *"$expected"*) ;;
    *) fail "$message (missing: $expected)" ;;
  esac
}

assert_not_contains() {
  local output unexpected message
  output="$1"
  unexpected="$2"
  message="$3"
  case "$output" in
    *"$unexpected"*) fail "$message (unexpected: $unexpected)" ;;
    *) ;;
  esac
}

make_app "$APPLICATIONS_DIR/Raycast.app"
make_app "$APPLICATIONS_DIR/Utilities/Disk Helper.app"
make_app "$USER_APPLICATIONS_DIR/Visual Studio Code.app"
mkdir -p "$APPLICATIONS_DIR/Broken.app/Contents"
make_app "$APPLICATIONS_DIR/Vendor/Products/Too Deep.app"
make_app "$TEST_ROOT/Linked Source.app"
ln -s "$TEST_ROOT/Linked Source.app" "$APPLICATIONS_DIR/Linked.app"

if move_path_to_trash "$APPLICATIONS_DIR/Linked.app"; then
  fail "a symlink must fail safely instead of trashing its target"
fi
[ -L "$APPLICATIONS_DIR/Linked.app" ] || fail "symlink was unexpectedly removed"
[ -e "$TEST_ROOT/Linked Source.app/Contents/Info.plist" ] || fail "symlink target was removed"

no_args_output=$(main)
list_output=$(main --list)
assert_equal "$no_args_output" "$list_output" "no arguments and --list should match"
assert_contains "$list_output" "Installed applications" "list should have a header"
assert_contains "$list_output" "$APPLICATIONS_DIR/Raycast.app" "list should include direct applications"
assert_contains "$list_output" "$APPLICATIONS_DIR/Utilities/Disk Helper.app" "list should include one nested level"
assert_contains "$list_output" "$USER_APPLICATIONS_DIR/Visual Studio Code.app" "list should include user applications"
assert_contains "$list_output" "$APPLICATIONS_DIR/Linked.app" "list should include valid app symlinks"
assert_contains "$list_output" "Total: 4" "list should report the total"
assert_not_contains "$list_output" "$APPLICATIONS_DIR/Broken.app" "list should exclude bundles without Info.plist"
assert_not_contains "$list_output" "Too Deep.app" "list should exclude deeply nested bundles"

for linked_target in "$APPLICATIONS_DIR/Linked.app" "Linked"; do
  set +e
  linked_output=$(main --yes "$linked_target" 2>&1)
  status=$?
  set -e
  assert_equal "1" "$status" "symlink apps must be rejected before uninstall"
  assert_contains "$linked_output" "Cannot uninstall a symlink app:" "symlink failure should explain the problem"
  assert_not_contains "$linked_output" "Checking for running processes" "symlink app should stop before process handling"
  [ -L "$APPLICATIONS_DIR/Linked.app" ] || fail "symlink app was removed"
  [ -e "$TEST_ROOT/Linked Source.app/Contents/Info.plist" ] || fail "linked app was removed"
done

expected_discovery=$(printf "%s\n" \
  "$APPLICATIONS_DIR/Linked.app" \
  "$APPLICATIONS_DIR/Raycast.app" \
  "$APPLICATIONS_DIR/Utilities/Disk Helper.app" | LC_ALL=C sort -f)
duplicate_discovery=$(discover_applications "$APPLICATIONS_DIR" "$APPLICATIONS_DIR")
assert_equal "$expected_discovery" "$duplicate_discovery" "discovery should sort and deduplicate applications"

resolve_application "RAYCAST" "${APPLICATION_ROOTS[@]}"
assert_equal "$APPLICATIONS_DIR/Raycast.app" "$RESOLVED_APP_PATH" "matching should be case-insensitive"

resolve_application "raycast.APP" "${APPLICATION_ROOTS[@]}"
assert_equal "$APPLICATIONS_DIR/Raycast.app" "$RESOLVED_APP_PATH" "matching should accept an app suffix"

resolve_application "visual studio" "${APPLICATION_ROOTS[@]}"
assert_equal "$USER_APPLICATIONS_DIR/Visual Studio Code.app" "$RESOLVED_APP_PATH" "matching should accept one unique partial match"

case_distinct_discovery=$(printf "%s\n" \
  "/Applications/Foo.app" \
  "/Applications/foo.app" \
  "/Applications/Foo.app" | sort_applications)
assert_equal $'/Applications/Foo.app\n/Applications/foo.app' "$case_distinct_discovery" "sorting should deduplicate only byte-identical paths"

case_distinct_resolution=$(
  discover_applications() {
    printf "%s\n" "/Applications/Foo.app" "/Applications/foo.app"
  }
  set +e
  resolve_application "foo" "unused-root"
  status=$?
  set -e
  printf "%s:%s\n" "$status" "${#RESOLUTION_MATCHES[@]}"
)
assert_equal "2:2" "$case_distinct_resolution" "case-distinct exact matches should both remain ambiguous"

make_app "$USER_APPLICATIONS_DIR/Raycast.app"
set +e
resolve_application "raycast" "${APPLICATION_ROOTS[@]}"
status=$?
set -e
assert_equal "2" "$status" "duplicate exact matches should be ambiguous"
assert_equal "2" "${#RESOLUTION_MATCHES[@]}" "ambiguous exact matches should be reported"

make_app "$USER_APPLICATIONS_DIR/Ray Notes.app"
set +e
resolve_application "ray" "${APPLICATION_ROOTS[@]}"
status=$?
set -e
assert_equal "2" "$status" "multiple partial matches should be ambiguous"

set +e
resolve_application "does-not-exist" "${APPLICATION_ROOTS[@]}"
status=$?
set -e
assert_equal "1" "$status" "an unknown application should not resolve"

assert_list_conflict() {
  local output status description
  description="$1"
  shift
  set +e
  output=$(main --list "$@" 2>&1)
  status=$?
  set -e
  assert_equal "1" "$status" "--list should reject $description"
  assert_contains "$output" "Cannot combine --list" "--list conflict should be clear"
}

assert_list_conflict "--yes" --yes
assert_list_conflict "--dry-run" --dry-run
assert_list_conflict "--verbose" --verbose
assert_list_conflict "an application argument" "$APPLICATIONS_DIR/Raycast.app"
assert_list_conflict "--bundle-id" --bundle-id com.example.App

for invalid_id in '' 'com.example.*' '../App' 'com..App' 'com.example/App' 'com.example.App;echo' 'App' '--yes'; do
  set +e
  invalid_id_output=$(main --bundle-id "$invalid_id" 2>&1)
  status=$?
  set -e
  assert_equal "1" "$status" "unsafe bundle IDs should fail"
  assert_not_contains "$invalid_id_output" "Finding app data" "invalid IDs should stop before discovery"
done

for args in '--bundle-id' '--bundle-id com.example.App --bundle-id com.example.Other' '--bundle-id com.example.App Target.app'; do
  set +e
  argument_output=$(IFS=' '; main $args 2>&1)
  status=$?
  set -e
  assert_equal "1" "$status" "invalid bundle ID arguments should fail"
  assert_not_contains "$argument_output" "Finding app data" "invalid arguments should stop before discovery"
done

set +e
missing_target_output=$(main --yes 2>&1)
status=$?
set -e
assert_equal "1" "$status" "uninstall options without a target should fail"
assert_contains "$missing_target_output" "Missing app path" "missing target should be clear"

set +e
invalid_path_output=$(main "$TEST_ROOT/Missing.app" 2>&1)
status=$?
set -e
assert_equal "1" "$status" "an invalid explicit path should fail"
assert_contains "$invalid_path_output" "Cannot find app plist" "invalid paths should not fall back to name matching"

if [ -x /usr/libexec/PlistBuddy ] && [ -x /usr/bin/plutil ]; then
  # Fixture runs never contact Finder, inspect real processes, or request sudo.
  sleep() { :; }
  pgrep() { return 1; }
  sudo() { fail "unexpected sudo in fixture cleanup"; }

  DIRECT_APP="$TEST_ROOT/Direct Fixture.app"
  mkdir -p "$DIRECT_APP/Contents"
  /usr/bin/plutil -create xml1 "$DIRECT_APP/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string com.example.uninstall-fixture "$DIRECT_APP/Contents/Info.plist"

  dry_run_output=$(main --dry-run "$DIRECT_APP" 2>&1)
  assert_contains "$dry_run_output" "Confirmation: dry-run" "dry-run should remain non-interactive"
  [ -e "$DIRECT_APP/Contents/Info.plist" ] || fail "dry-run removed the fixture app"

  decline_output=$(printf "n\n" | main "$DIRECT_APP" 2>&1)
  assert_contains "$decline_output" "Uninstall cancelled by user" "declining should cancel the uninstall"
  [ -e "$DIRECT_APP/Contents/Info.plist" ] || fail "declining removed the fixture app"

  mkdir -p "$HOME/Library/Caches/com.example.uninstall-fixture"
  mkdir -p "$HOME/Library/Application Scripts/com.example.uninstall-fixture"
  mkdir -p "$TEST_ROOT/Trash"
  touch "$TEST_ROOT/fail-cache"
  /usr/bin/osascript() {
    local target arg
    for arg in "$@"; do target="$arg"; done
    printf '%s\n' "$target" >> "$TEST_ROOT/trash-calls"
    if [ "$target" = "$HOME/Library/Caches/com.example.uninstall-fixture" ] && [ -e "$TEST_ROOT/fail-cache" ]; then
      printf 'Finder: permission denied (-5000)\n' >&2
      return 1
    fi
    mv "$target" "$TEST_ROOT/Trash/$(wc -l < "$TEST_ROOT/trash-calls" | tr -d ' ')"
  }

  set +e
  partial_output=$(main --yes "$DIRECT_APP" 2>&1)
  status=$?
  set -e
  assert_equal "1" "$status" "a partial Trash move should fail the command"
  assert_contains "$partial_output" "Finder: permission denied (-5000)" "Finder errors should remain visible"
  assert_contains "$partial_output" "Move to Trash failed: $HOME/Library/Caches/com.example.uninstall-fixture" "partial failure should identify only the failed path"
  assert_contains "$partial_output" "Trash action: partial (moved: 1, failed: 1)" "failure should not count the kept app as moved"
  assert_contains "$partial_output" "App bundle kept so cleanup can be retried" "failure should explain recovery"
  [ -e "$DIRECT_APP/Contents/Info.plist" ] || fail "cleanup failure removed the app needed for retry"
  assert_not_contains "$(cat "$TEST_ROOT/trash-calls")" "$DIRECT_APP" "the app must not be trashed after a data failure"

  rm "$TEST_ROOT/fail-cache"
  retry_output=$(main --yes "$DIRECT_APP" 2>&1)
  assert_contains "$retry_output" "Trash action: moved (moved: 2, failed: 0)" "retry should finish cleanup"
  [ ! -e "$DIRECT_APP" ] || fail "successful retry left the app behind"
  assert_equal "$DIRECT_APP" "$(tail -n 1 "$TEST_ROOT/trash-calls")" "the app bundle must move last"

  mkdir -p "$HOME/Library/Containers/com.example.uninstall-fixture"
  mkdir -p "$HOME/Library/Caches/com.example.uninstall-fixture.Other"
  mkdir -p "$HOME/Library/Application Support/Direct Fixture"
  mkdir -p "$HOME/Library/LaunchAgents"
  unrelated_launch="$HOME/Library/LaunchAgents/com.example.unrelated.plist"
  /usr/bin/plutil -create xml1 "$unrelated_launch"
  /usr/bin/plutil -insert Label -string com.example.unrelated "$unrelated_launch"
  prefix_launch="$HOME/Library/LaunchAgents/com.example.uninstall-fixture.Other.plist"
  /usr/bin/plutil -create xml1 "$prefix_launch"
  /usr/bin/plutil -insert Label -string com.example.uninstall-fixture.Other "$prefix_launch"
  app_path=""
  related_bundle_ids=(com.example.uninstall-fixture)
  if launchd_matches_plist "$prefix_launch"; then
    fail "a longer launch-item bundle ID must not match the cleanup ID"
  fi
  exact_launch="$TEST_ROOT/exact-launch.plist"
  /usr/bin/plutil -create xml1 "$exact_launch"
  /usr/bin/plutil -insert Label -string com.example.uninstall-fixture "$exact_launch"
  launchd_matches_plist "$exact_launch" || fail "an exact launch-item bundle ID should match"

  cleanup_preview=$(main --dry-run --bundle-id com.example.uninstall-fixture 2>&1)
  assert_contains "$cleanup_preview" "Confirmation: dry-run" "bundle ID cleanup must support dry runs"
  assert_contains "$cleanup_preview" "Total matched: 1" "bundle ID cleanup should match only the exact leftover"
  assert_contains "$cleanup_preview" "No launch items found" "an absent app path must not match unrelated launch items"
  assert_not_contains "$cleanup_preview" "com.example.uninstall-fixture.Other" "cleanup must not match an ID prefix"
  [ -d "$HOME/Library/Containers/com.example.uninstall-fixture" ] || fail "dry run removed leftover data"

  cleanup_decline=$(printf 'n\n' | main --bundle-id com.example.uninstall-fixture 2>&1)
  assert_contains "$cleanup_decline" "Uninstall cancelled by user" "bundle ID cleanup should ask once"
  [ -d "$HOME/Library/Containers/com.example.uninstall-fixture" ] || fail "declining removed leftover data"

  cleanup_output=$(printf 'y\n' | main --bundle-id com.example.uninstall-fixture 2>&1)
  assert_contains "$cleanup_output" "Trash action: moved (moved: 1, failed: 0)" "cleanup should work after the app is gone"
  [ ! -e "$HOME/Library/Containers/com.example.uninstall-fixture" ] || fail "confirmed cleanup left matched data"
  [ -d "$HOME/Library/Caches/com.example.uninstall-fixture.Other" ] || fail "cleanup removed another app's data"
  [ -d "$HOME/Library/Application Support/Direct Fixture" ] || fail "bundle ID cleanup guessed an app name"
  [ -e "$unrelated_launch" ] || fail "cleanup removed an unrelated launch item"
  [ -e "$prefix_launch" ] || fail "cleanup removed a longer bundle ID's launch item"

  empty_cleanup=$(main --yes --bundle-id com.example.uninstall-fixture 2>&1)
  assert_contains "$empty_cleanup" "Trash action: skipped (no matches)" "completed cleanup should be safe to repeat"
fi

printf "All uninstall tests passed.\n"
