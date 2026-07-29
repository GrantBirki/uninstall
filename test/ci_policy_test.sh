#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW_DIR="$ROOT_DIR/.github/workflows"
RELEASE_WORKFLOW="$WORKFLOW_DIR/release.yml"

fail() {
  echo "GitHub Actions policy: $1" >&2
  exit 1
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

while IFS= read -r uses_line; do
  uses=$(sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]#].*$//' <<< "$uses_line")
  [[ "$uses" == ./* ]] && continue

  action="${uses%%@*}"
  case "$action" in
    actions/checkout|actions/upload-artifact|actions/download-artifact|actions/attest|openai/fence) ;;
    *) fail "action is not allowlisted: $action" ;;
  esac

  if [[ ! "$uses" =~ @[0-9a-fA-F]{40}$ ]] && [[ ! "$uses" =~ @sha256:[0-9a-fA-F]{64}$ ]]; then
    fail "action is not pinned to an immutable digest: $uses"
  fi
done < <(grep -R -h -E 'uses:[[:space:]]*' "$WORKFLOW_DIR")

checkout_count=$(grep -R -h -E 'uses:[[:space:]]*actions/checkout@' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
nonpersisted_count=$(grep -R -h -E '^[[:space:]]+persist-credentials:[[:space:]]*false[[:space:]]*$' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
if [[ "$checkout_count" != "$nonpersisted_count" ]]; then
  fail "every checkout must set persist-credentials: false"
fi
sha_ref_count=$(grep -R -h -F 'ref: ${{ github.sha }}' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
if [[ "$checkout_count" != "$sha_ref_count" ]]; then
  fail "every checkout must use the immutable event commit"
fi
shallow_count=$(grep -R -h -E '^[[:space:]]+fetch-depth:[[:space:]]*1[[:space:]]*$' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
if [[ "$checkout_count" != "$shallow_count" ]]; then
  fail "every checkout must fetch only the event commit"
fi
checkout_verification_count=$(grep -R -h -F 'git rev-parse HEAD' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
if [[ "$checkout_count" != "$checkout_verification_count" ]]; then
  fail "every checkout must verify HEAD against GITHUB_SHA"
fi

expected_fence='openai/fence@2cf00d32716021a106bb59fcdc1c978c22a3def3 # pin@v0.9.2'
while IFS= read -r fence_line; do
  [[ "$fence_line" == *"$expected_fence"* ]] || fail "Fence must use the verified v0.9.2 release pin: $fence_line"
done < <(grep -R -h -E 'uses:[[:space:]]*openai/fence@' "$WORKFLOW_DIR")

ubuntu_job_count=$(grep -R -h -E '^[[:space:]]+runs-on:[[:space:]]*ubuntu-24\.04[[:space:]]*$' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
fence_count=$(grep -R -h -E 'uses:[[:space:]]*openai/fence@' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
fence_name_count=$(grep -R -h -E '^[[:space:]]+- name:[[:space:]]*fence[[:space:]]*$' "$WORKFLOW_DIR" | wc -l | tr -d ' ')
if [[ "$ubuntu_job_count" != "$fence_count" || "$fence_count" != "$fence_name_count" ]]; then
  fail "every supported Ubuntu job must start with a step named fence"
fi
if awk '
  function finish_step() {
    if (is_fence && is_audit && allows_artifacts) {
      invalid = 1
    }
  }

  /^[[:space:]]+- name:/ {
    finish_step()
    is_fence = 0
    is_audit = 0
    allows_artifacts = 0
  }

  /uses:[[:space:]]*openai\/fence@/ { is_fence = 1 }
  /^[[:space:]]+mode:[[:space:]]*audit[[:space:]]*$/ { is_audit = 1 }
  /^[[:space:]]+allow_github_artifacts:[[:space:]]*true[[:space:]]*$/ { allows_artifacts = 1 }

  END {
    finish_step()
    exit invalid ? 0 : 1
  }
' "$RELEASE_WORKFLOW"; then
  fail "Fence audit mode cannot enable GitHub artifact access"
fi

grep -q "branches:" "$RELEASE_WORKFLOW" || fail "release workflow must restrict its branch"
grep -q -- "- main" "$RELEASE_WORKFLOW" || fail "release workflow must target main"
grep -F -q "github.workflow_sha == github.sha" "$RELEASE_WORKFLOW" || fail "release workflow definition must match the source commit"
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
