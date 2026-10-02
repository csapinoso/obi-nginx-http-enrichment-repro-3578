# Repro status vs #3578 / @mmat11

## What maintainers asked for

From [issue comment 5931550365](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues/3578#issuecomment-5931550365):

> if we can manage to get a **reproducible script** which makes the code fail this way, we can understand why and how it breaks

“Fail this way” means OBI DEBUG like:

```text
error while parsing http request or response, falling back to manual HTTP info parsing
  reqErr=<nil>  respErr="malformed MIME header line: \" \""
  respErr="malformed MIME header: missing colon: \"0\""
```

…and nginx **server** spans **without** enriched `Authorization` (legacy path).

## What is reproducible today

| Piece | Command | Status |
|-------|---------|--------|
| **#1 — Cluster capture + fixtures** | `./scripts/verify-fixtures-package.sh` | **Complete (offline)** — frozen 2026-10-02 dev capture; regenerate with `./scripts/capture-from-dev.sh` during stock **v0.11.0** + debug GitOps window |
| **Parser failure (same `respErr` strings)** | `go run ./cmd/parse-buffer-lab` | **Works everywhere** — shows which response buffer shapes trigger fallback in `httpSafeParseResponse` |
| **#2 — Full stack (nginx + OBI v0.11.0 + enrichment)** | `REQUIRE_EBPF_FALLBACK=1 ./run-repro.sh` | **WIP** — compose runs but rarely emits DEBUG fallback on Docker Desktop; use [docs/LINUX_REPRO_OPTIONS.md](./docs/LINUX_REPRO_OPTIONS.md) |

So: **#1** is ready to attach to #3578 (fixtures + capture script + parser lab). **#2** (deterministic compose/CI repro) is **not** done — do not claim `./run-repro.sh` alone satisfies the maintainer bar until `REQUIRE_EBPF_FALLBACK=1` passes on Linux.

## Why compose is hard

Wire HTTP from nginx to the client is usually valid. The cluster failure is consistent with **misaligned response large buffers** in OBI (capture/stitching), not with a bad JSON upstream. Guessing upstream shapes (`/large`, chunked, `proxy_buffering off`) did not reproduce fallback on Docker Desktop in our tests.

## What is needed to finish the eBPF repro

1. **Capture** one failing response buffer from a stock v0.11.0 DEBUG session on nginx/openresty (www-web or this compose on **Linux** with `pid: host` — see `docker-compose.hostpid.yml`).
2. **Replay** those bytes on the client-facing path, or identify the traffic/nginx setting that produces the same buffer layout.
3. Extend `./run-repro.sh` to **require** DEBUG fallback + missing `http.request.header.authorization` on nginx spans (exit non-zero otherwise).

Until step 3 passes on a clean Linux Docker host (or in CI), treat the zip as **work in progress** plus `parse-buffer-lab` for the parser half of the story.
