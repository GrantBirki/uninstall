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
  move_path_to_trash() {
    case "$1" in
      "$HOME/Library/Caches/com.example.uninstall-fixture") return 1 ;;
      *) return 0 ;;
    esac
  }

  set +e
  partial_output=$(main --yes "$DIRECT_APP" 2>&1)
  status=$?
  set -e
  assert_equal "1" "$status" "a partial Trash move should fail the command"
  assert_contains "$partial_output" "Move to Trash failed: $HOME/Library/Caches/com.example.uninstall-fixture" "partial failure should identify only the failed path"
  assert_contains "$partial_output" "Trash action: partial (moved: 1, failed: 1)" "partial failure should report accurate counts"
fi

printf "All uninstall tests passed.\n"
