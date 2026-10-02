#!/usr/bin/env bash
# Verify #1 deliverable (capture script + frozen fixtures) without cluster access.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/fixtures"
missing=0
require() {
  if [[ ! -s "$1" ]]; then
    echo "MISSING or empty: $1" >&2
    missing=1
  fi
}

require "$FIX/capture-run.meta"
require "$FIX/curl-get-root.sanitized.txt"
require "$FIX/obi-parse-debug-sample-line.sanitized.txt"
require "$FIX/obi-parse-debug-ingress-http11.sanitized.txt"
require "$FIX/ingress-capture.meta"

if ! grep -q 'falling back to manual HTTP info parsing' "$FIX/obi-parse-debug-sample-line.sanitized.txt"; then
  echo "FAIL: sample line missing fallback DEBUG marker" >&2
  missing=1
fi
if ! grep -q 'missing colon' "$FIX/obi-parse-debug-sample-line.sanitized.txt"; then
  echo "FAIL: sample line missing respErr class" >&2
  missing=1
fi

if [[ ! -x "$ROOT/scripts/capture-from-dev.sh" ]]; then
  echo "MISSING executable: scripts/capture-from-dev.sh" >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
echo "OK: fixture package (#1) is complete for offline handoff."
echo "    Regenerate live: ./scripts/capture-from-dev.sh (stock v0.11.0 + debug on dev)."
