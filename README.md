# OBI v0.11.0 — nginx reverse proxy HTTP header enrichment repro

Minimal **docker-compose** repro for [opentelemetry-ebpf-instrumentation#3578](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues/3578):

stock **OpenTelemetry eBPF Instrumentation (OBI) v0.11.0** with HTTP header enrichment enabled, **nginx** as HTTP/1.1 reverse proxy, and an optional upstream that can trigger **legacy parse path** behavior (missing response large buffer or response parse fallback).

Maintainer request: **docker-compose**, **HTTP/1.1**, investigate response buffers / parse — not legacy-path enrichment patches.

## Requirements

- Docker Engine + Compose v2
- Linux (native or **Docker Desktop** Linux VM)
- ~2 GB disk for images

On Docker Desktop (macOS/Windows), OBI needs:

- `privileged: true`
- Bind mount `/sys/fs/bpf:/sys/fs/bpf`

## Quick start

```bash
./run-repro.sh
```

This builds the stack, waits for OBI to attach to nginx, sends authenticated traffic on several routes, and prints:

- OBI DEBUG lines (`missing large buffer`, `falling back to manual HTTP info parsing`)
- Whether the OpenTelemetry Collector debug exporter saw `http.request.header.authorization` on nginx **server** spans per route

## Manual run

```bash
docker compose up --build -d
./scripts/traffic.sh http://127.0.0.1:8080/small
docker compose logs obi | rg -i 'falling back|missing large buffer'
docker compose logs otel-collector | rg 'http.request.header.authorization'
docker compose down
```

## Layout

| Service | Role |
|---------|------|
| `upstream` | Go `net/http` server: `/small`, `/large`, `/chunked`, `/html` |
| `nginx` | HTTP/1.1 reverse proxy; `/unbuffered/*` disables `proxy_buffering` |
| `obi` | Sidecar (`pid: nginx`), stock image `ebpf-instrument:v0.11.0` |
| `otel-collector` | OTLP gRPC `:4317`, `debug` exporter (detailed) |

Traffic: **client → nginx:8080 → upstream:8080**.

## OBI config (summary)

Matches [http-header-enrichment-demo](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/tree/main/examples/http-header-enrichment-demo) style rules:

- `track_request_headers: true`
- `buffer_sizes.http: 8192`
- Enrichment: include request header `authorization`
- `log_level: debug`
- Traces → `otel-collector:4317`

## Expected outcomes (stock v0.11.0)

Enrichment runs only on the **full HTTP request+response parse path** in OBI. On the **legacy** path, spans still get method/status/route but **not** enriched headers.

| Route | Intent |
|-------|--------|
| `/small` | Small JSON via nginx (often **full parse** → authorization attribute present) |
| `/unbuffered/large` | Large body + `proxy_buffering off` (targets **missing response large buffer**) |
| `/unbuffered/chunked` | Chunked encoding + unbuffered proxy |
| `/html` | HTML + extra response headers (closer to real pages) |

Your kernel/Docker version may differ; `run-repro.sh` reports which routes showed fallback logs and which spans lacked authorization.

## Packaging

```bash
git archive --format=zip --prefix=obi-nginx-http-enrichment-repro-3578/ HEAD
# or: tar -czvf obi-nginx-http-enrichment-repro-3578.tgz --exclude=.git .
```

Share the archive or push to a public gist/repo and link from GitHub issue #3578.

## License

Apache-2.0 (same as opentelemetry-ebpf-instrumentation).
