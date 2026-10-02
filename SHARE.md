# Sending this repro to OBI maintainers

**#1 (capture + fixtures) is OK to send now.** **#2 (compose/CI eBPF repro)** is WIP — see [REPRO_STATUS.md](./REPRO_STATUS.md) and [docs/LINUX_REPRO_OPTIONS.md](./docs/LINUX_REPRO_OPTIONS.md).

Verify offline package:

```bash
./scripts/verify-fixtures-package.sh
go run ./cmd/parse-buffer-lab
```

Suggested GitHub comment on [#3578](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues/3578):

---

@mmat11 — repro package for the parse-fallback + missing Authorization path on nginx/openresty **server** spans (stock **v0.11.0**).

**A. eBPF evidence (scripted capture + fixtures)**

- `./scripts/capture-from-dev.sh` — re-run on our cluster when we temporarily pin stock v0.11.0 + `log_level: debug`.
- Committed **`fixtures/`** from 2026-10-02: ingress **HTTP/1.1** traffic to openresty `GET /` (~402 KiB HTML, Terranova-style proxy buffers). DEBUG shows `reqErr=<nil>` and response-side `respErr` e.g. `malformed MIME header: missing colon: "00550"` (same family as `"0"` in your comment). See `obi-parse-debug-sample-line.sanitized.txt`.
- **Note:** grep the **cluster-wide** OBI logs after ingress traffic; co-located OBI on the www-web node often shows **zero** fallback lines.

**B. Parser step (deterministic, no cluster)**

```bash
go run ./cmd/parse-buffer-lab
```

Same `httpSafeParseResponse` / `http.ReadResponse` failures as the DEBUG `respErr` strings.

**C. docker-compose (WIP for full eBPF trigger)**

```bash
./run-repro.sh
REQUIRE_EBPF_FALLBACK=1 ./run-repro.sh   # intended sign-off on Linux CI
```

We have not yet made compose reliably hit the fallback path; tracking on Ubuntu GHA + openresty/hostpid tweaks.

Happy to PR under `examples/` once **C** is green on Linux.

---

Attach zip (`obi-nginx-http-enrichment-repro-3578.zip`) or public repo link.
