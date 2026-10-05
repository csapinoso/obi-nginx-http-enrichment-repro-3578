#!/usr/bin/env bash
# Capture PRO-11748 / OBI #3578 parse-fallback DEBUG + response wire shape from dev www-web.
#
# Prerequisites:
#   - kubectl access to gcp-dev-use1 (or set CONTEXT)
#   - Temporary dev OBI: stock v0.11.0 + log_level: debug (GitOps probe; revert after capture)
#   - Namespace pluto-us-test-www
#
# Usage:
#   ./scripts/capture-from-dev.sh
#   FIXTURE_DIR=/tmp/out ./scripts/capture-from-dev.sh
#
# Writes sanitized files under fixtures/ (or FIXTURE_DIR).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="${FIXTURE_DIR:-$ROOT/fixtures}"
CONTEXT="${CONTEXT:-gcp-dev-use1}"
WWW_NS="${WWW_NS:-pluto-us-test-www}"
OBI_NS="${OBI_NS:-opentelemetry-ebpf-system}"
INGRESS_HOST="${INGRESS_HOST:-www-web-pluto-us-test-www.gcp-dev-use1.pluto.tv}"
AUTH_TOKEN="${AUTH_TOKEN:-pro-11748-capture-$(date +%s)}"
TRAFFIC_COUNT="${TRAFFIC_COUNT:-40}"

mkdir -p "$FIXTURE_DIR"
META="$FIXTURE_DIR/capture-run.meta"
sanitized_curl_headers() {
  sed -E 's/Bearer [^ ]+/Bearer <redacted>/g; s/(CBS_COM=)[^;]+/\1<redacted>/g'
}

echo "capture_run $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$META"
echo "context=$CONTEXT ingress=$INGRESS_HOST token_prefix=${AUTH_TOKEN%%-*}" | tee -a "$META"

WWW_POD="$(kubectl --context "$CONTEXT" -n "$WWW_NS" get pod -l app.kubernetes.io/name=www-web -o jsonpath='{.items[0].metadata.name}')"
NODE="$(kubectl --context "$CONTEXT" -n "$WWW_NS" get pod "$WWW_POD" -o jsonpath='{.spec.nodeName}')"
OBI_LOCAL="$(kubectl --context "$CONTEXT" -n "$OBI_NS" get pods -o wide --field-selector "spec.nodeName=$NODE" | awk '/otel-obi/{print $1; exit}')"
OBI_IMAGE="$(kubectl --context "$CONTEXT" -n "$OBI_NS" get ds otel-obi -o jsonpath='{.spec.template.spec.containers[0].image}')"
LOG_LEVEL="$(kubectl --context "$CONTEXT" -n "$OBI_NS" get cm otel-obi -o yaml | grep 'log_level:' || echo 'log_level: (default)')"

{
  echo "www_web_pod=$WWW_POD"
  echo "www_web_node=$NODE"
  echo "obi_colocated=$OBI_LOCAL"
  echo "obi_image=$OBI_IMAGE"
  echo "$LOG_LEVEL"
  echo "auth_token=$AUTH_TOKEN"
} | tee -a "$META"

if [[ "$OBI_IMAGE" != *":v0.11.0"* ]] && [[ "$OBI_IMAGE" != *"v0.11.0"* ]]; then
  echo "WARN: OBI image is not stock v0.11.0 — parse-fallback capture may not match #3578 (custom agent may enrich legacy path)." >&2
fi

echo "==> In-pod wire sample (loopback GET /)"
kubectl --context "$CONTEXT" -n "$WWW_NS" exec "$WWW_POD" -c www-web -- \
  sh -c "curl -sv -H 'Authorization: Bearer ${AUTH_TOKEN}' http://127.0.0.1/ 2>&1 | head -45" \
  | sanitized_curl_headers | tee "$FIXTURE_DIR/curl-get-root-loopback.sanitized.txt"

echo "==> Ingress traffic (HTTP/1.1, Authorization)"
curl -skv --http1.1 -H "Authorization: Bearer ${AUTH_TOKEN}" "https://${INGRESS_HOST}/" 2>&1 | head -45 \
  | sanitized_curl_headers | tee "$FIXTURE_DIR/curl-get-root-ingress-http11.sanitized.txt" || true

for _ in $(seq 1 "$TRAFFIC_COUNT"); do
  curl -sk --http1.1 -o /dev/null -H "Authorization: Bearer ${AUTH_TOKEN}" "https://${INGRESS_HOST}/" || true
done
sleep 10

echo "==> OBI parse-path (co-located pod only: $OBI_LOCAL)"
: > "$FIXTURE_DIR/obi-parse-debug-colocated.sanitized.txt"
if [[ -n "$OBI_LOCAL" ]]; then
  kubectl --context "$CONTEXT" -n "$OBI_NS" logs "$OBI_LOCAL" --since=8m 2>&1 \
    | grep -iE 'missing large buffer|falling back|error while parsing' \
    | sed -E 's/respErr="[^"]{0,220}.*/respErr="<redacted>"/' \
    | tee "$FIXTURE_DIR/obi-parse-debug-colocated.sanitized.txt" || true
fi

echo "==> OBI parse-path (cluster-wide, last 8m)"
kubectl --context "$CONTEXT" -n "$OBI_NS" logs -l app.kubernetes.io/name=obi --since=8m --max-log-requests=50 2>&1 \
  | grep -iE 'missing large buffer|falling back|error while parsing|HTTP response large buffer shape' \
  | sed -E 's/respErr="[^"]{0,220}.*/respErr="<redacted>"/' \
  | tee "$FIXTURE_DIR/obi-parse-debug-cluster.sanitized.txt" | head -20

# One sample line with respErr class preserved (no secrets in respErr)
kubectl --context "$CONTEXT" -n "$OBI_NS" logs -l app.kubernetes.io/name=obi --since=8m --max-log-requests=50 2>&1 \
  | grep -m1 'falling back to manual HTTP info parsing' \
  | sed -E 's/(Bearer|token=)[^ ]+/\1<redacted>/gi' \
  | tee "$FIXTURE_DIR/obi-parse-debug-sample-line.sanitized.txt" || true

COLOC_COUNT=$(wc -l < "$FIXTURE_DIR/obi-parse-debug-colocated.sanitized.txt" | tr -d ' ')
CLUSTER_COUNT=$(wc -l < "$FIXTURE_DIR/obi-parse-debug-cluster.sanitized.txt" | tr -d ' ')
echo "fallback_lines_colocated=$COLOC_COUNT fallback_lines_cluster=$CLUSTER_COUNT" | tee -a "$META"

if [[ "$CLUSTER_COUNT" -eq 0 ]]; then
  echo "NOTE: no fallback lines — confirm log_level=debug and stock v0.11.0, increase TRAFFIC_COUNT, retry." >&2
  exit 1
fi

echo "OK: fixtures written under $FIXTURE_DIR"
