#!/usr/bin/env bash
# Send authenticated GETs to a base URL (path included in URL).
set -euo pipefail

BASE_URL="${1:?usage: traffic.sh http://127.0.0.1:8080/small}"
COUNT="${2:-15}"
TOKEN="${AUTH_TOKEN:-repro-$(date +%s)}"

for _ in $(seq 1 "$COUNT"); do
  curl -sS --retry 2 --retry-delay 1 --max-time 120 -o /dev/null \
    -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}" || exit 1
done
echo "sent ${COUNT} requests to ${BASE_URL} (Authorization: Bearer ${TOKEN})"
