#!/usr/bin/env bash
# Brute-force traffic patterns; grep OBI for parse fallback (local dev only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

$COMPOSE up --build -d 2>/dev/null
COMPOSE="${COMPOSE:-docker compose}"
$COMPOSE up --build -d

wait_obi() {
  for _ in $(seq 1 90); do
    if $COMPOSE logs obi 2>&1 | grep -q 'Enabling trace information parsing'; then
      sleep 5
      return 0
    fi
    sleep 1
  done
  return 1
}
wait_obi

AUTH="Bearer hunt-$(date +%s)"
check() {
  local name="$1"
  shift
  "$@" >/dev/null 2>&1 || true
  sleep 3
  if $COMPOSE logs obi 2>&1 | tail -500 | grep -qi 'falling back to manual HTTP info parsing'; then
    echo "HIT: $name"
    $COMPOSE logs obi 2>&1 | grep -i 'falling back' | tail -3
    exit 0
  fi
  echo "miss: $name"
}

check pipeline bash -c "printf 'GET /small HTTP/1.1\r\nHost: localhost\r\nAuthorization: ${AUTH}\r\n\r\nGET /small HTTP/1.1\r\nHost: localhost\r\nAuthorization: ${AUTH}\r\n\r\n' | nc -w 2 127.0.0.1 8080"
check keepalive bash -c "for i in \$(seq 1 50); do curl -sS -o /dev/null -H 'Authorization: ${AUTH}' -H 'Connection: keep-alive' http://127.0.0.1:8080/small; done"
check unbuf_large bash -c "for i in \$(seq 1 30); do curl -sS -o /dev/null -H 'Authorization: ${AUTH}' 'http://127.0.0.1:8080/unbuffered/large?kb=32'; done"
check chunked bash -c "for i in \$(seq 1 30); do curl -sS -o /dev/null -H 'Authorization: ${AUTH}' http://127.0.0.1:8080/unbuffered/chunked; done"
check html bash -c "for i in \$(seq 1 30); do curl -sS -o /dev/null -H 'Authorization: ${AUTH}' http://127.0.0.1:8080/html; done"
check parallel bash -c "seq 1 40 | xargs -P 20 -I{} curl -sS -o /dev/null -H 'Authorization: ${AUTH}' http://127.0.0.1:8080/small"

echo "No fallback triggered in hunt set"
exit 1
