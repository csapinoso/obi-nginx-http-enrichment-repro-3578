<!-- Paste into https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues/3578 -->

@mmat11 — we put together a repro package for the parse-fallback branch on nginx/openresty **server** spans (stock **OBI v0.11.0**), where enriched `Authorization` is missing because `HTTPInfoEventToSpan` never gets a full successful req+resp parse.

**Repo:** https://github.com/csapinoso/obi-nginx-http-enrichment-repro-3578  
**CI:** https://github.com/csapinoso/obi-nginx-http-enrichment-repro-3578/actions (smoke green; sign-off gate still red — expected until compose hits the same path as our cluster)

---

### A. eBPF evidence (reproducible today)

**Frozen capture (2026-10-02, GKE dev, openresty `www-web`, stock v0.11.0 + `log_level: debug`):**

- Ingress **HTTP/1.1** burst to `GET /` (~402 KiB HTML, Terranova `proxy_buffers 16×16k`).
- OBI DEBUG (sanitized sample in repo):

  ```
  error while parsing http request or response, falling back to manual HTTP info parsing
  reqErr=<nil> respErr="malformed MIME header: missing colon: \"00550\""
  ```

  (`"00550"` is the same `respErr` *family* as `"0"` in [your comment](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues/3578#issuecomment-5931550365).)

- **Gotcha:** after ingress traffic, grep **cluster-wide** OBI logs — the daemonset pod co-located with the www-web node often shows **zero** fallback lines; fallback showed up on another node’s `otel-obi` pod.

Artifacts: `fixtures/obi-parse-debug-sample-line.sanitized.txt`, `fixtures/README.md`. Re-capture script (needs temporary stock v0.11.0 on cluster): `./scripts/capture-from-dev.sh`.

---

### B. Parser step (deterministic, no K8s)

Shows which response buffer shapes fail the same helper as OBI (`httpSafeParseResponse` / `http.ReadResponse`):

```bash
git clone https://github.com/csapinoso/obi-nginx-http-enrichment-repro-3578.git
cd obi-nginx-http-enrichment-repro-3578
go run ./cmd/parse-buffer-lab
```

Example output includes `malformed MIME header: missing colon: "0"`.

---

### C. docker-compose (WIP — full eBPF trigger)

HTTP/1.1, OpenResty reverse proxy, enrichment config aligned with the header-enrichment demo, OBI **v0.11.0**:

```bash
./run-repro.sh                                    # smoke
COMPOSE_FILES="-f docker-compose.yml -f docker-compose.signoff.yml" \
  REQUIRE_EBPF_FALLBACK=1 ./run-repro.sh          # Linux sign-off stack (host pid/network + Terranova buffers + burst traffic)
```

On Ubuntu CI we consistently get **successful parse + `http.request.header.authorization` on `/` spans** — not the failure mode above. We’re iterating on the sign-off stack; happy to PR under `examples/` once `REQUIRE_EBPF_FALLBACK=1` goes green.

---

If a raw buffer capture from the failing path would help upstream more than compose, we can share sanitized DEBUG + `parse-buffer-lab` cases first and keep chasing compose parity in the open repo.
