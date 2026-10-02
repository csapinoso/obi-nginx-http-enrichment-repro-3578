#!/usr/bin/env bash
# Rapid HTTP/1.1 burst (similar to capture-from-dev ingress traffic window).
set -euo pipefail

URL="${1:-http://127.0.0.1:8080/}"
COUNT="${2:-40}"
TOKEN="${AUTH_TOKEN:-repro-burst-$(date +%s)}"
PARALLEL="${PARALLEL:-1}"

if [[ "$PARALLEL" == "1" ]]; then
  for _ in $(seq 1 "$COUNT"); do
    curl -sS --http1.1 --max-time 120 -o /dev/null \
      -H "Authorization: Bearer ${TOKEN}" "${URL}" &
  done
  wait
else
  for _ in $(seq 1 "$COUNT"); do
    curl -sS --http1.1 --max-time 120 -o /dev/null \
      -H "Authorization: Bearer ${TOKEN}" "${URL}"
  done
fi
echo "burst ${COUNT} HTTP/1.1 GETs to ${URL} (Authorization: Bearer ${TOKEN})"
