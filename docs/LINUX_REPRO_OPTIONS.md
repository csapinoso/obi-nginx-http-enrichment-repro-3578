# Options to accomplish #2 (Linux eBPF repro) with what we have now

Goal: `REQUIRE_EBPF_FALLBACK=1 ./run-repro.sh` **passes** on Linux — OBI DEBUG shows parse fallback and nginx spans lack `http.request.header.authorization` on the failing route (stock **v0.11.0**).

We already have:

- **Fixtures** from dev (`fixtures/`, `./scripts/capture-from-dev.sh`)
- **Compose** with Terranova-style proxy buffers + ~392 KiB HTML upstream (`/`, `/appshell-like`)
- **`go run ./cmd/parse-buffer-lab`** (deterministic parser `respErr` family)
- **Confirmed** fallback on real dev under ingress + cluster-wide grep (not yet in local compose)

Mac Docker Desktop is **not** the sign-off host.

---

## Option A — GitHub Actions on `ubuntu-latest` (recommended)

**Status:** Implemented — `.github/workflows/repro-3578.yml`

- Job `parser-and-fixtures`: `go run ./cmd/parse-buffer-lab`, `./scripts/verify-fixtures-package.sh`
- Job `ebpf-compose-smoke`: bridge openresty sidecar
- Job `ebpf-repro-signoff`: `docker-compose.signoff.yml` (openresty + Terranova buffers + host pid/network) + `scripts/traffic-burst.sh`

**Pros:** Repeatable, shareable link for mmat11, no laptop OS dependency.  
**Cons:** First green run may need further compose tweaks; expect red until fallback matches cluster.

---

## Option B — Linux VM on your Mac (Lima / Multipass / Rancher Linux)

**Effort:** Medium one-time setup.

Clone the stand-alone repo inside the VM, install Docker, run `REQUIRE_EBPF_FALLBACK=1 ./run-repro.sh`.

**Pros:** Interactive debugging (`docker compose logs obi`).  
**Cons:** You maintain the VM; same compose may still not fail until Option C/D.

---

## Option C — Compose hardening (incremental, combine with A or B)

Try in order (each is a small diff):

1. **openresty** sidecar or replace `nginx:alpine` with an image closer to www-web (`openresty/openresty`), same `proxy-buffers.conf`.
2. **`docker-compose.hostpid.yml`** on Linux only (`pid: host`, `network_mode: host`) — matches OBI `examples/nginx` pattern.
3. **Default traffic** only on `/` (appshell-like body), drop `/small` from the failure assertion path.
4. **`context_propagation: all`** (already set) — compare with `disabled` once to see if parse/enrichment split changes (diagnostic, not the upstream fix).

Dev showed fallback with **real** openresty + large HTML; compose may need **openresty**, not only buffer sizes.

---

## Option D — Dev cluster as the “reference repro” (hybrid)

Keep **docker-compose** as the maintainer-facing *layout*, but document a **second command** that reuses dev:

```bash
./scripts/capture-from-dev.sh   # proves eBPF failure mode on stock v0.11.0
go run ./cmd/parse-buffer-lab   # proves parser step
```

Post to #3578: “eBPF repro = scripted capture + fixtures; local compose WIP; CI on Ubuntu tracking compose parity.”

**Pros:** Honest, uses access you already have; matches captured DEBUG.  
**Cons:** Not a fully offline repro for mmat11 without Paramount cluster (mitigate with public compose + CI).

---

## Option E — Minimal in-cluster repro manifest (optional)

Apply a trimmed **nginx/openresty + large upstream** Deployment in `pluto-us-test-www` (or reuse `opentelemetry-ebpf-helm3/scripts/pro-11748/k8s/repro.yaml` extended with appshell-like upstream) for one hour, run traffic, grep OBI — same as capture script but isolated from www-web.

**Pros:** Highest fidelity to GKE + openresty.  
**Cons:** RBAC, Argo noise, not vendor-neutral on cluster.

---

## Suggested sequence

1. **Land Option A** (GHA) on the stand-alone repo with current compose.  
2. If red, apply **Option C1 + C2** until green or logs show new clues.  
3. Post **Option D** package to #3578 while CI iterates.  
4. Use **Option B** only if you want local Linux iteration without pushing every try.

When `REQUIRE_EBPF_FALLBACK=1` passes on Ubuntu CI, update `REPRO_STATUS.md` to “complete” and refresh the zip.
