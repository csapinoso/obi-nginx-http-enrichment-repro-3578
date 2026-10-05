#!/usr/bin/env bash
# Build OBI agent from local clone (legacy-path fix + response buffer shape DEBUG).
set -euo pipefail

OBI_SRC="${OBI_SRC:-$HOME/Work/Open Source/opentelemetry-ebpf-instrumentation}"
OBI_BRANCH="${OBI_BRANCH:-fix/legacy-path-http-header-enrichment}"
IMAGE="${OBI_LOCAL_IMAGE:-obi-pro-11748:local}"

if [[ "$(uname -m)" == "arm64" ]]; then
  PLATFORM="${PLATFORM:-linux/arm64}"
else
  PLATFORM="${PLATFORM:-linux/amd64}"
fi

if [[ ! -d "$OBI_SRC/.git" ]]; then
  echo "OBI source not found: $OBI_SRC" >&2
  exit 1
fi

cd "$OBI_SRC"
git checkout "$OBI_BRANCH"
REV="$(git rev-parse --short HEAD)"
echo "Building $IMAGE from $OBI_BRANCH@$REV ($PLATFORM)"

docker buildx build --platform "$PLATFORM" --load \
  -t "$IMAGE" -f Dockerfile \
  --build-arg "RELEASE_VERSION=v0.11.0-pro-11748" \
  --build-arg "RELEASE_REVISION=$REV" \
  .

echo "OK: $IMAGE"
echo "Run: COMPOSE_FILES=\"-f docker-compose.yml -f docker-compose.openresty.yml -f docker-compose.local-obi.yml\" ./run-repro.sh"
