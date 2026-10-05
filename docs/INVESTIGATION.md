# Source investigation (stock OBI v0.11.0 / #3578)

Local clone: `~/Work/Open Source/opentelemetry-ebpf-instrumentation` (branch `fix/legacy-path-http-header-enrichment` for Paramount PR **#3579**).

## Two separate problems

| Layer | What happens | Paramount impact |
|-------|----------------|------------------|
| **A. Response buffer / parse** | Generic/cpp path captures a **response large buffer**, but `http.ReadResponse` fails (`respErr`, e.g. `missing colon: "00550"`) | DEBUG fallback; no full parse |
| **B. Enrichment on fallback (v0.11.0 bug)** | On parse failure, **v0.11.0** returns `httpRequestToSpan` only — **no `httpEnricher.Enrich`** | No `Authorization` on span even when request buffer is fine |

**#3579** fixes **B** (`httpLegacySpanFromEvent` parses request buffer and enriches).  
**#3578** (mmat11) is about **A** — why the response buffer is wrong for nginx/openresty + large HTML.

## Userspace path (v0.11.0 tag)

`pkg/ebpf/common/http_transform.go` — `HTTPInfoEventToSpan`:

1. `HasLargeBuffers == 1` → `extractTCPLargeBuffer` for req + resp (HTTP uses `KindLayerApp`).
2. If `hasResponse` and enrichment enabled → `http.ReadRequest` + `httpSafeParseResponse`.
3. **v0.11.0 on any parse error:**

   ```go
   return httpRequestToSpan(event, requestBuffer), false, nil  // no enrichment
   ```

4. **Fix branch on parse error or missing response:**

   ```go
   return httpLegacySpanFromEvent(parseCtx, event, requestBuffer), false, nil  // enrich from request
   ```

Cluster capture matches step 3 with `reqErr=<nil>`, `respErr` set → **B alone explains missing Authorization on stock v0.11.0**.

## What `respErr` means

`httpSafeParseResponse` → `net/http.ReadResponse`. Errors like `malformed MIME header: missing colon: "00550"` mean the parser is still reading **headers** but the next line looks like body/content (no `:`). Typical causes:

- Response snapshot **starts mid-stream** (status line or header block incomplete).
- **Header/body boundary missing** in the stitched large buffer (`\r\n\r\n` not present before body bytes).
- **Multi-chunk stitching** appends body bytes where the parser expects more headers (large HTML + many `Set-Cookie` lines + proxy buffering).

See `go run ./cmd/parse-buffer-lab` for minimal byte patterns that produce the same `respErr` family.

## v0.11.0 vs main (follow-ups for upstream)

- **Large-buffer map key:** v0.11.0 `extractTCPLargeBuffer` keys primarily on **trace ID** (no span ID in call sites). Main added span ID (**#3470** — overlapping Go buffers). Worth asking if nginx/generic HTTP can mix buffers under load on v0.11.0.
- **BPF capture:** `bpf/generictracer/protocol_http.h` / tail calls — next debug step is **`protocol_debug`** (or `OBI_PROTOCOL_DEBUG`) plus logging raw `LargeBufferExtract` in userspace to compare wire bytes vs nginx `curl` capture.

## What we can do without mmat11

1. **Ship #3579** (custom agent) — restores Authorization on fallback path regardless of **A**.
2. **Next capture window (stock v0.11.0 + debug):** enable protocol/large-buffer debug; dump **one** failing response `largebuf` (hex) from `HTTPInfoEventToSpan` and add to `parse-buffer-lab` + optional upstream unit test.
3. **BPF deep dive:** trace where generic HTTP **response** large buffer init/append triggers for **server** spans on reverse proxy (nginx worker → client direction).
4. **Do not block on compose sign-off** for Paramount prod — CI sign-off is parity research; cluster fixtures already prove **A** on real openresty.

## Tests to run locally

```bash
cd ~/Work/Open\ Source/opentelemetry-ebpf-instrumentation
git checkout fix/legacy-path-http-header-enrichment
go test ./pkg/ebpf/common/ -run TestHTTPInfoEventToSpan_LegacyPathHeaderEnrichment -count=1
```

Compare v0.11.0 tag (test absent; fallback skips enricher).
