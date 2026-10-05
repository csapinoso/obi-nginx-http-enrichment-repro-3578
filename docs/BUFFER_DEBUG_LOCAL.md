# Response buffer shape DEBUG (local + GKE)

When `httpSafeParseResponse` fails, OBI logs (fork branch `fix/legacy-path-http-header-enrichment`):

```text
HTTP response large buffer shape on parse failure
  responseBufferLen=…
  headerTerminatorOffset=…   # \r\n\r\n index, or -1
  startsWithHTTP=true|false
  head64Hex=…
  tail64Hex=…
```

Hex only — safe to paste in #3578 comments after capture.

## Local (Docker)

```bash
# 1. Build agent from ~/Work/Open Source/opentelemetry-ebpf-instrumentation
chmod +x scripts/build-local-obi.sh
./scripts/build-local-obi.sh

# 2. Compose with local image (openresty sidecar)
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.openresty.yml -f docker-compose.local-obi.yml" \
  ./run-repro.sh

docker compose … logs obi 2>&1 | rg -i 'parse failure|head64Hex|falling back'
```

Parse fallback is **still rare** on Mac compose; this wiring validates the **log line** and enrichment (#3579). For real `00550`-class buffers, use GKE capture.

## GKE (fidelity)

1. Build/push image (Paramount script):

   ```bash
   cd opentelemetry-ebpf-helm3
   OBI_BRANCH=fix/legacy-path-http-header-enrichment \
   IMAGE_TAG=pro-11748-buffer-debug \
   ./scripts/pro-11748/build-obi-pr-image.sh
   ```

2. Short GitOps pin: stock **v0.11.0** + debug **or** custom tag above on dev OBI.

3. `./scripts/capture-from-dev.sh` then grep:

   ```bash
   kubectl … logs -l app.kubernetes.io/name=obi --since=15m | \
     rg 'HTTP response large buffer shape|head64Hex|falling back'
   ```

4. Compare `responseBufferLen` / `headerTerminatorOffset` to `fixtures/curl-get-root.sanitized.txt` Content-Length (~402 KiB).

## Unit test (no Docker)

```bash
cd ~/Work/Open\ Source/opentelemetry-ebpf-instrumentation
go test ./pkg/internal/largebuf/ -run TestProbeShape -count=1
```
