#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="${ROOT}/.secrets.baseline"
REPORT_DIR="${SECRET_SCAN_REPORT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/symphony-secret-scan.XXXXXX")}"
DETECT_SECRETS_EXCLUDE='(^|[\\/])(\.git|\.secrets\.baseline|elixir[\\/]deps|elixir[\\/]_build|elixir[\\/]cover|elixir[\\/]log|elixir[\\/]logs|elixir[\\/]tmp|elixir[\\/]doc|elixir[\\/]priv[\\/]static[\\/]assets)([\\/]|$)'

require_command() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    cat >&2 <<EOF
Missing required command: ${name}

Install locally with:
  brew install gitleaks trufflehog detect-secrets
EOF
    exit 127
  fi
}

require_command gitleaks
require_command trufflehog
require_command detect-secrets

resolve_python() {
  local candidate
  local probe

  for candidate in python3 python; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
      continue
    fi

    probe="$($candidate -c 'print("symphony-python-ok")' 2>/dev/null || true)"
    if [ "$probe" = "symphony-python-ok" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Missing a working Python interpreter (tried python3, then python)." >&2
  return 127
}

PYTHON_BIN="$(resolve_python)"

if [ ! -f "$BASELINE" ]; then
  echo "Missing detect-secrets baseline: ${BASELINE}" >&2
  echo "Regenerate it after manual review with:" >&2
  echo "  detect-secrets scan --exclude-files '${DETECT_SECRETS_EXCLUDE}' > .secrets.baseline" >&2
  exit 64
fi

mkdir -p "$REPORT_DIR"

echo "Secret scan reports: ${REPORT_DIR}"

echo "==> gitleaks"
gitleaks detect \
  --source "$ROOT" \
  --config "${ROOT}/.gitleaks.toml" \
  --redact \
  --verbose \
  --report-format json \
  --report-path "${REPORT_DIR}/gitleaks.json"

echo "==> trufflehog verified secrets"
TRUFFLEHOG_REPO_URI="file://${ROOT}"

if command -v cygpath >/dev/null 2>&1; then
  TRUFFLEHOG_REPO_URI="file://$(cygpath -m "$ROOT")"
fi

(
  export MSYS_NO_PATHCONV=1
  export MSYS2_ARG_CONV_EXCL='*'

  trufflehog git "$TRUFFLEHOG_REPO_URI" \
    --results=verified \
    --json \
    --no-update \
    --fail
) >"${REPORT_DIR}/trufflehog.jsonl"

echo "==> detect-secrets baseline gate"
DETECT_SECRETS_CURRENT="${REPORT_DIR}/detect-secrets-current.json"

(cd "$ROOT" && detect-secrets scan --exclude-files "$DETECT_SECRETS_EXCLUDE") \
  >"$DETECT_SECRETS_CURRENT"

"$PYTHON_BIN" - "$BASELINE" "$DETECT_SECRETS_CURRENT" <<'PY'
import json
import sys


def load_findings(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)

    findings = set()
    for filename, entries in data.get("results", {}).items():
        normalized_filename = filename.replace("\\", "/")
        for entry in entries:
            findings.add(
                (
                    normalized_filename,
                    entry.get("type"),
                    entry.get("hashed_secret"),
                )
            )

    return findings


baseline_path, current_path = sys.argv[1:3]
baseline = load_findings(baseline_path)
current = load_findings(current_path)
new_findings = sorted(current - baseline)

if new_findings:
    print("detect-secrets found new candidates not present in .secrets.baseline:", file=sys.stderr)
    for filename, secret_type, _hashed_secret in new_findings:
        print(f"  - {filename}: {secret_type}", file=sys.stderr)
    print("Review the findings and update .secrets.baseline only for confirmed false positives.", file=sys.stderr)
    sys.exit(1)

print(f"detect-secrets findings are covered by baseline ({len(current)} current candidates).")
PY

echo "Secret scan completed successfully."
