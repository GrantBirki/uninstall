#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"
RELEASE_WORKFLOW="$WORKFLOW_DIR/release.yml"
CHECKOUT_ACTION_PATTERN="^[[:space:]]*(-[[:space:]]*)?(uses|\"uses\"|'uses')[[:space:]]*:[[:space:]]*[\"']?actions/checkout@"

fail() {
  echo "GitHub Actions policy: $1" >&2
  exit 1
}

validate_workflow_steps() {
  awk -v expected_fence="openai/fence@2cf00d32716021a106bb59fcdc1c978c22a3def3" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    function unquote(value, first, last, single_quote) {
      value = trim(value)
      first = substr(value, 1, 1)
      last = substr(value, length(value), 1)
      single_quote = sprintf("%c", 39)
      if ((first == "\"" && last == "\"") || (first == single_quote && last == single_quote)) {
        value = substr(value, 2, length(value) - 2)
      }
      return value
    }

    function indentation(value, original) {
      original = value
      sub(/^[[:space:]]*/, "", value)
      return length(original) - length(value)
    }

    function parse_pair(text, top_level, raw, separator, key, value) {
      separator = index(text, ":")
      if (separator == 0) {
        return
      }

      key = unquote(substr(text, 1, separator - 1))
      value = unquote(substr(text, separator + 1))

      if (top_level) {
        if (key == "name") {
          step_name = value
        } else if (key == "uses") {
          step_uses = value
          if (raw ~ /#[[:space:]]*pin@v0\.9\.2[[:space:]]*$/) {
            fence_pin_comment = "true"
          }
        } else if (key == "with" && value == "") {
          in_with = 1
          with_indent = current_indent
        }
        return
      }

      if (key == "persist-credentials") {
        persist_credentials = value
      } else if (key == "ref") {
        checkout_ref = value
      } else if (key == "fetch-depth") {
        fetch_depth = value
      } else if (key == "mode") {
        fence_mode = value
      } else if (key == "allow_github_artifacts") {
        allow_github_artifacts = value
      }
    }

    function report(message) {
      print FILENAME ": " message > "/dev/stderr"
      invalid = 1
    }

    function validate_action(reference, action, digest, original) {
      if (reference == "" || reference ~ /^\.\//) {
        return
      }

      original = reference
      action = reference
      sub(/@.*/, "", action)
      if (action != "actions/checkout" && action != "actions/upload-artifact" &&
          action != "actions/download-artifact" && action != "actions/attest" &&
          action != "openai/fence") {
        report("action is not allowlisted: " action)
      }

      sub(/^[^@]*@/, "", reference)
      digest = reference
      sub(/^sha256:/, "", digest)
      if ((reference ~ /^sha256:/ && (length(digest) != 64 || digest !~ /^[0-9a-fA-F]+$/)) ||
          (reference !~ /^sha256:/ && (length(reference) != 40 || reference !~ /^[0-9a-fA-F]+$/))) {
        report("action is not pinned to an immutable digest: " original)
      }
    }

    function finish_step() {
      if (!in_step) {
        return
      }

      validate_action(step_uses)
      action = step_uses
      sub(/@.*/, "", action)

      if (first_step && (job_runner == "ubuntu-24.04" || job_runner == "ubuntu-latest") && action != "openai/fence") {
        report("supported Ubuntu job does not start with Fence")
      }

      if (action == "actions/checkout") {
        if (persist_credentials != "false") {
          report("checkout step " step_number " must set persist-credentials: false")
        }
        if (checkout_ref != "${{ github.sha }}") {
          report("checkout step " step_number " must use the immutable event commit")
        }
        if (fetch_depth != "1") {
          report("checkout step " step_number " must set fetch-depth: 1")
        }
      } else if (action == "openai/fence") {
        if (step_name != "fence") {
          report("Fence step " step_number " must be named fence")
        }
        if (step_uses != expected_fence || !fence_pin_comment) {
          report("Fence step " step_number " must use the verified v0.9.2 release pin")
        }
        if (!first_step) {
          report("Fence step " step_number " must be the first meaningful step")
        }
        if (fence_mode == "audit" && allow_github_artifacts == "true") {
          report("Fence audit mode cannot enable GitHub artifact access")
        }
      }
    }

    function reset_step() {
      step_name = ""
      step_uses = ""
      persist_credentials = ""
      checkout_ref = ""
      fetch_depth = ""
      fence_mode = ""
      allow_github_artifacts = ""
      fence_pin_comment = 0
      in_with = 0
      with_indent = -1
    }

    {
      raw_line = $0
      clean_line = $0
      sub(/[[:space:]]*#.*/, "", clean_line)
      if (clean_line ~ /^[[:space:]]*$/) {
        next
      }

      current_indent = indentation(clean_line)
      content = substr(clean_line, current_indent + 1)

      if (in_steps && current_indent <= steps_indent) {
        finish_step()
        in_steps = 0
        in_step = 0
      }

      if (!in_steps) {
        if (current_indent == 2 && content ~ /^[^:]+:[[:space:]]*$/) {
          current_runner = ""
        }

        separator = index(content, ":")
        if (separator > 0) {
          key = unquote(substr(content, 1, separator - 1))
          value = unquote(substr(content, separator + 1))
          if (key == "runs-on") {
            current_runner = value
          } else if (key == "uses") {
            validate_action(value)
          } else if (key == "steps") {
            in_steps = 1
            steps_indent = current_indent
            job_runner = current_runner
            step_number = 0
          }
        }
        next
      }

      if (current_indent == steps_indent + 2 && content ~ /^-[[:space:]]*/) {
        finish_step()
        reset_step()
        in_step = 1
        step_number++
        first_step = (step_number == 1)
        step_indent = current_indent
        sub(/^-[[:space:]]*/, "", content)
        if (content != "") {
          parse_pair(content, 1, raw_line)
        }
        next
      }

      if (!in_step) {
        next
      }

      if (current_indent == step_indent + 2) {
        in_with = 0
        with_indent = -1
        parse_pair(content, 1, raw_line)
        next
      }

      if (in_with && current_indent > with_indent) {
        parse_pair(content, 0, raw_line)
      }
    }

    END {
      finish_step()
      exit invalid ? 1 : 0
    }
  ' "$1"
}

if grep -R -n -E '^[[:space:]]*pull_request_target:' "$WORKFLOW_DIR" >/dev/null; then
  fail "pull_request_target is prohibited"
fi

if grep -R -n -E 'uses:[[:space:]]*actions/cache@' "$WORKFLOW_DIR" >/dev/null; then
  fail "the shared Actions cache is prohibited"
fi

while IFS= read -r cache_line; do
  value="${cache_line#*:}"
  value="${value%%#*}"
  value=$(printf '%s' "$value" | tr -d "[:space:]\"'")
  if [[ "$value" != "false" ]]; then
    fail "setup-action caches must be explicitly disabled: $cache_line"
  fi
done < <(grep -R -h -E '^[[:space:]]+(bundler-)?cache:' "$WORKFLOW_DIR" || true)

unsafe_checkout_fixture=$(
  printf '%s\n' \
    'jobs:' \
    '  test:' \
    '    runs-on: macos-latest' \
    '    steps:' \
    '      - "uses": actions/checkout@1111111111111111111111111111111111111111 # trailing uses: attacker/action@main' \
    '        env:' \
    '          persist-credentials: false' \
    '          ref: ${{ github.sha }}' \
    '          fetch-depth: 1' \
    '        with:' \
    '          persist-credentials: true' \
    '      - uses: actions/checkout@1111111111111111111111111111111111111111' \
    '        with:' \
    '          persist-credentials: false' \
    '          ref: ${{ github.sha }}' \
    '          fetch-depth: 1'
)
if validate_workflow_steps <(printf '%s\n' "$unsafe_checkout_fixture") >/dev/null 2>&1; then
  fail "step-scoped checkout regression fixture passed unexpectedly"
fi

safe_parser_fixture=$(
  printf '%s\n' \
    'jobs:' \
    '  test:' \
    '    runs-on: macos-latest' \
    '    steps:' \
    '      - "uses": actions/checkout@1111111111111111111111111111111111111111 # trailing uses: attacker/action@main' \
    '        with:' \
    '          persist-credentials: false' \
    '          ref: ${{ github.sha }}' \
    '          fetch-depth: 1' \
    '      - run: echo "uses: attacker/action@main"'
)
validate_workflow_steps <(printf '%s\n' "$safe_parser_fixture") >/dev/null 2>&1 || fail "action parser regression fixture failed"

quoted_fence_fixture=$(
  printf '%s\n' \
    'jobs:' \
    '  test:' \
    '    runs-on: ubuntu-24.04' \
    '    steps:' \
    '      - name: fence' \
    "        'uses': openai/fence@2cf00d32716021a106bb59fcdc1c978c22a3def3 # pin@v0.9.2" \
    '        with:' \
    '          mode: audit'
)
validate_workflow_steps <(printf '%s\n' "$quoted_fence_fixture") >/dev/null 2>&1 || fail "quoted Fence action regression fixture failed"

spoofed_fence_fixture=$(
  printf '%s\n' \
    'jobs:' \
    '  test:' \
    '    runs-on: ubuntu-24.04' \
    '    steps:' \
    "      - 'uses': openai/fence@2cf00d32716021a106bb59fcdc1c978c22a3def3 # pin@v0.9.2" \
    '        name: restrict network' \
    '      - name: fence' \
    '        run: echo spoof'
)
if validate_workflow_steps <(printf '%s\n' "$spoofed_fence_fixture") >/dev/null 2>&1; then
  fail "step-scoped Fence regression fixture passed unexpectedly"
fi

for workflow in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [[ -e "$workflow" ]] || continue
  validate_workflow_steps "$workflow" || fail "unsafe workflow step configuration"
done

checkout_count=$(grep -R -h -E "$CHECKOUT_ACTION_PATTERN" "$WORKFLOW_DIR" | wc -l | tr -d ' ')
checkout_verification_count=$(grep -R -h -F 'git rev-parse HEAD' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
if [[ "$checkout_count" != "$checkout_verification_count" ]]; then
  fail "every checkout must verify HEAD against GITHUB_SHA"
fi

grep -q "branches:" "$RELEASE_WORKFLOW" || fail "release workflow must restrict its branch"
grep -q -- "- main" "$RELEASE_WORKFLOW" || fail "release workflow must target main"
grep -F -q "github.workflow_sha == github.sha" "$RELEASE_WORKFLOW" || fail "release workflow definition must match the source commit"
grep -E -q "needs\\.build\\.result == 'success'.*needs\\.release\\.result == 'success'" "$RELEASE_WORKFLOW" || fail "release info must require successful build and release jobs"
if grep -q "workflow_dispatch:" "$RELEASE_WORKFLOW"; then
  fail "release workflow must not have a manual dispatch path"
fi

[[ "$(grep -c 'id-token: write' "$RELEASE_WORKFLOW")" == "1" ]] || fail "OIDC permission must exist in exactly one isolated job"
[[ "$(grep -c 'attestations: write' "$RELEASE_WORKFLOW")" == "1" ]] || fail "attestation permission must exist in exactly one isolated job"
[[ "$(grep -c 'artifact-metadata: write' "$RELEASE_WORKFLOW")" == "1" ]] || fail "artifact metadata permission must exist in exactly one isolated job"
[[ "$(grep -c 'contents: write' "$RELEASE_WORKFLOW")" == "1" ]] || fail "contents write permission must exist in exactly one publication job"
[[ "$(grep -c 'environment: release' "$RELEASE_WORKFLOW")" -ge 2 ]] || fail "attestation and publication must use the protected release environment"
grep -q -- "--source-digest" "$RELEASE_WORKFLOW" || fail "attestation verification must bind the source commit"
grep -q -- "--signer-digest" "$RELEASE_WORKFLOW" || fail "attestation verification must bind the signer workflow commit"

echo "GitHub Actions policy: OK"
