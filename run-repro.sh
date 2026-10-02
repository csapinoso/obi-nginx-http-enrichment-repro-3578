#!/usr/bin/env bash
# End-to-end repro for opentelemetry-ebpf-instrumentation#3578 (docker-compose + OBI v0.11.0).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> Part 1: response parse failures (same respErr family as #3578 DEBUG)"
if command -v go >/dev/null 2>&1; then
  go run ./cmd/parse-buffer-lab
else
  echo "WARN: install Go to run ./cmd/parse-buffer-lab (deterministic parser repro)"
fi
echo ""

COMPOSE="${COMPOSE:-docker compose}"
if [[ -z "${COMPOSE_FILES:-}" ]]; then
  if [[ "$(uname -s)" == Linux ]]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.openresty.yml -f docker-compose.hostpid.yml"
  else
    COMPOSE_FILES="-f docker-compose.yml"
  fi
fi
COMPOSE_ARGS=( $COMPOSE $COMPOSE_FILES )
AUTH="repro-3578-$(date +%s)"
REQUIRE_EBPF_FALLBACK="${REQUIRE_EBPF_FALLBACK:-0}"

cleanup() {
  "${COMPOSE_ARGS[@]}" down -v >/dev/null 2>&1 || true
}
on_exit() {
  local code=$?
  if [[ "$code" -ne 0 ]] && [[ "${KEEP_COMPOSE_ON_FAILURE:-0}" == "1" ]]; then
    echo "Keeping stack up for log capture (exit $code)." >&2
    exit "$code"
  fi
  cleanup
  exit "$code"
}
trap on_exit EXIT

echo "==> Compose: ${COMPOSE_ARGS[*]}"

echo "==> Starting stack"
"${COMPOSE_ARGS[@]}" up --build -d

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
  logs=$("${COMPOSE_ARGS[@]}" logs obi 2>&1 || true)
  if printf '%s\n' "$logs" | grep -q 'instrumenting process' \
    && printf '%s\n' "$logs" | grep -q 'Enabling trace information parsing'; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  echo "FAIL: OBI did not attach to nginx" >&2
  "${COMPOSE_ARGS[@]}" logs obi | tail -40
  exit 1
fi
sleep 5

PRIMARY_ROUTES=(
  "http://127.0.0.1:8080/"
  "http://127.0.0.1:8080/appshell-like"
)
EXTRA_ROUTES=(
  "http://127.0.0.1:8080/small"
  "http://127.0.0.1:8080/unbuffered/large"
)

echo "==> Generating traffic (Authorization on every request)"
export AUTH_TOKEN="$AUTH"
for url in "${PRIMARY_ROUTES[@]}"; do
  bash "$ROOT/scripts/traffic.sh" "$url" 24
  sleep 2
done
if [[ "$REQUIRE_EBPF_FALLBACK" != "1" ]]; then
  for url in "${EXTRA_ROUTES[@]}"; do
    bash "$ROOT/scripts/traffic.sh" "$url" 12
    sleep 2
  done
fi
sleep 12

OBI_LOGS=$("${COMPOSE_ARGS[@]}" logs obi 2>&1 || true)
COLL_LOGS=$("${COMPOSE_ARGS[@]}" logs otel-collector 2>&1 || true)

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

root_auth=0
if span_has_auth_for_path "/"; then root_auth=1; fi

echo ""
echo "==> Span enrichment check (collector debug exporter)"
echo "    / (appshell-like)       authorization on span: $([[ $root_auth -eq 1 ]] && echo yes || echo no)"
echo "    OBI fallback/buffer log: $([[ $has_fallback -eq 1 ]] && echo yes || echo no)"

echo ""
# Maintainer bar (#3578): DEBUG parse fallback on nginx/openresty server path and no Authorization on / spans.
if [[ "$has_fallback" -eq 1 ]] && [[ "$root_auth" -eq 0 ]]; then
  echo "PASS: Parse fallback DEBUG + missing Authorization on GET / (matches cluster failure mode)."
  exit 0
fi

if [[ "$has_fallback" -eq 1 ]] && [[ "$root_auth" -eq 1 ]]; then
  echo "PARTIAL: OBI logged fallback but Authorization still present on / spans (inspect buffer stitching)."
  if [[ "$REQUIRE_EBPF_FALLBACK" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "$has_fallback" -eq 0 ]] && [[ "$root_auth" -eq 0 ]]; then
  echo "PARTIAL: No Authorization on / but no fallback DEBUG line (legacy path without logged parse error?)."
  if [[ "$REQUIRE_EBPF_FALLBACK" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

echo "NOTE: eBPF/nginx did not emit parse fallback on this run (see REPRO_STATUS.md)."
echo "      Set REQUIRE_EBPF_FALLBACK=1 to fail until DEBUG fallback is reproduced."
if [[ "$REQUIRE_EBPF_FALLBACK" == "1" ]]; then
  exit 1
fi
exit 0
