# Sending this repro to OBI maintainers

Suggested GitHub comment on [#3578](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/issues/3578):

---

Thanks for the docker-compose / HTTP/1.1 guidance. We packaged a **standalone repro** (no vendor-specific config):

**Contents:** nginx 1.26 → Go upstream, stock OBI **v0.11.0** sidecar (`pid: nginx`), otel-collector debug exporter, enrichment config aligned with `http-header-enrichment-demo`.

**Run:**

```bash
./run-repro.sh
```

**Routes exercised:**

- `/small` — small JSON (control-style path)
- `/unbuffered/large` — 16 KiB body, `proxy_buffering off`
- `/unbuffered/chunked` — chunked response, unbuffered
- `/html` — HTML + cookies

The script prints OBI DEBUG lines (`missing large buffer`, `falling back to manual HTTP info parsing`) and whether `http.request.header.authorization` appears on nginx server spans per route.

On Docker Desktop we consistently see enrichment on all routes (no fallback DEBUG yet). On our Kubernetes nginx/openresty workloads we see parse fallback and missing Authorization on server spans with the same agent config — we're still aligning upstream response shape with this compose stack.

Happy to PR this under `examples/` if you want it in-tree.

---

Attach **zip** or link to a public repo/gist.
