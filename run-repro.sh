#!/usr/bin/env bash
# End-to-end repro for opentelemetry-ebpf-instrumentation#3578 (docker-compose + OBI v0.11.0).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

COMPOSE="${COMPOSE:-docker compose}"
AUTH="repro-3578-$(date +%s)"

cleanup() {
  $COMPOSE down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Starting stack"
$COMPOSE up --build -d

echo "==> Waiting for nginx"
for _ in $(seq 1 45); do
  if curl -sf http://127.0.0.1:8080/small >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Waiting for OBI to attach to nginx"
ready=0
for _ in $(seq 1 90); do
  logs=$($COMPOSE logs obi 2>&1 || true)
  if printf '%s\n' "$logs" | grep -q 'instrumenting process' \
    && printf '%s\n' "$logs" | grep -q 'Enabling trace information parsing'; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  echo "FAIL: OBI did not attach to nginx" >&2
  $COMPOSE logs obi | tail -40
  exit 1
fi
sleep 5

ROUTES=(
  "http://127.0.0.1:8080/small"
  "http://127.0.0.1:8080/unbuffered/large"
  "http://127.0.0.1:8080/unbuffered/chunked"
  "http://127.0.0.1:8080/html"
)

echo "==> Generating traffic (Authorization on every request)"
export AUTH_TOKEN="$AUTH"
for url in "${ROUTES[@]}"; do
  bash "$ROOT/scripts/traffic.sh" "$url" 12
  sleep 2
done
sleep 12

OBI_LOGS=$($COMPOSE logs obi 2>&1 || true)
COLL_LOGS=$($COMPOSE logs otel-collector 2>&1 || true)

echo ""
echo "==> OBI parse-path signals (sanitized)"
printf '%s\n' "$OBI_LOGS" | grep -iE 'missing large buffer|falling back to manual|error while parsing' \
  | sed -E 's/respErr="[^"]{0,160}.*/respErr="<redacted>"/' | tail -15 || echo "(none matched)"

has_fallback=0
if printf '%s\n' "$OBI_LOGS" | grep -qiE 'missing large buffer|falling back to manual'; then
  has_fallback=1
fi

span_has_auth_for_path() {
  local path="$1"
  # Collector debug exporter prints url.path then attributes on following lines.
  printf '%s\n' "$COLL_LOGS" | awk -v p="$path" '
    $0 ~ ("url.path: Str\\(" p "\\)") { inspan=1; block="" }
    inspan { block = block $0 "\n" }
    inspan && /Span #[0-9]+/ && block !~ ("url.path: Str\\(" p "\\)") { inspan=0 }
    END {
      if (block ~ /http\.request\.header\.authorization/) exit 0
      exit 1
    }
  '
}

small_auth=0
large_auth=0
if span_has_auth_for_path "/small"; then small_auth=1; fi
if span_has_auth_for_path "/unbuffered/large"; then large_auth=1; fi

echo ""
echo "==> Span enrichment check (collector debug exporter)"
echo "    /small                  authorization on span: $([[ $small_auth -eq 1 ]] && echo yes || echo no)"
echo "    /unbuffered/large       authorization on span: $([[ $large_auth -eq 1 ]] && echo yes || echo no)"
echo "    OBI fallback/buffer log: $([[ $has_fallback -eq 1 ]] && echo yes || echo no)"

echo ""
if [[ "$has_fallback" -eq 1 ]] && [[ "$small_auth" -eq 1 ]] && [[ "$large_auth" -eq 0 ]]; then
  echo "PASS: Repro shows legacy parse/buffer path on unbuffered large traffic and enrichment on /small."
  echo "      Share this directory (or zip) with maintainers — see README.md."
  exit 0
fi

if [[ "$has_fallback" -eq 1 ]]; then
  echo "PARTIAL: OBI logged fallback/buffer issues; span diff may vary by kernel/Docker."
  echo "         Inspect: docker compose logs obi | rg -i 'falling back|missing large'"
  exit 0
fi

if [[ "$small_auth" -eq 1 ]] && [[ "$large_auth" -eq 0 ]]; then
  echo "PARTIAL: Authorization missing on /unbuffered/large spans but no fallback DEBUG line yet."
  echo "         Still useful for #3578 — attach collector + OBI log excerpts."
  exit 0
fi

echo "NOTE: On this host all probed routes behaved the same (often: enrichment on every route)."
echo "      Try Linux bare metal or tune upstream ( /large?kb=32 ) and proxy_buffering."
echo "      Stack is valid for maintainers to iterate — see README.md."
exit 0
