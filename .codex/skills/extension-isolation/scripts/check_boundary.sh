#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)
strict=0
if [[ "${1:-}" == "--strict" ]]; then
  strict=1
elif [[ $# -gt 0 ]]; then
  printf 'usage: %s [--strict]\n' "$0" >&2
  exit 2
fi

cd "$repo_root"
failures=0
warnings=0

report_matches() {
  local label=$1
  shift
  local output
  output=$(rg -n --hidden --glob '!**/deps/**' --glob '!_build/**' --glob '!*.beam' "$@" || true)
  if [[ -n "$output" ]]; then
    printf '\n[%s]\n%s\n' "$label" "$output"
    return 1
  fi
  return 0
}

printf 'Extension isolation audit: %s\n' "$repo_root"

# Production Core may expose neutral contracts, but must not contain Lite
# business vocabulary or direct concrete extension references.
if ! report_matches 'Core production contains Lite vocabulary' \
  --glob 'elixir/lib/**' --glob 'elixir/config/**' --glob 'elixir/mix.exs' \
  'MaestroTapdGitlabLite|GITLAB_API_TOKEN|AI特殊工作流|AI模型等级|tapd_git_codex|SYMPHONY_GIT_OBJECT_CACHE_ROOT'; then
  failures=$((failures + 1))
fi

# Concrete Lite assets do not belong in Core bundled asset directories.
if ! report_matches 'Core owns Lite workflow/automation assets' \
  --glob 'elixir/priv/**' \
  'tapd/git/codex|AI特殊工作流|AI模型等级|GITLAB_API_TOKEN|repo-object-cache|repo-full-checkout|GitLab'; then
  failures=$((failures + 1))
fi

# Tests are evidence, not an excuse to add production coupling. Report them as
# warnings by default so existing characterization tests can be migrated.
if report_matches 'Core tests still mention concrete Lite implementation' \
  --glob 'elixir/test/**' \
  'MaestroTapdGitlabLite|GITLAB_API_TOKEN|AI特殊工作流|AI模型等级|tapd_git_codex'; then
  :
else
  warnings=$((warnings + 1))
fi

if (( strict == 1 && warnings > 0 )); then
  failures=$((failures + warnings))
fi

printf '\nAudit result: failures=%d warnings=%d\n' "$failures" "$warnings"
if (( failures > 0 )); then
  exit 1
fi
