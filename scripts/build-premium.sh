#!/usr/bin/env bash
# Build both premium-unlocked lago images.
#
# Usage:
#   ./scripts/build-premium.sh                # defaults to v1.45.1
#   ./scripts/build-premium.sh v1.46.0        # override upstream version
#
# Run from the repo root (uses repo dir as build context).

set -euo pipefail

LAGO_VERSION="${1:-v1.45.1}"
API_TAG="lago-api-premium:${LAGO_VERSION}"
FRONT_TAG="lago-front-premium:${LAGO_VERSION}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Building API image: ${API_TAG} ==="
docker build \
    --build-arg "LAGO_VERSION=${LAGO_VERSION}" \
    --file "${REPO_ROOT}/Dockerfile.api-premium" \
    --tag "${API_TAG}" \
    "${REPO_ROOT}"

echo
echo "=== Building FRONT image: ${FRONT_TAG} ==="
docker build \
    --build-arg "LAGO_VERSION=${LAGO_VERSION}" \
    --file "${REPO_ROOT}/Dockerfile.front-premium" \
    --tag "${FRONT_TAG}" \
    "${REPO_ROOT}"

echo
echo "=== Verifying API image ==="
docker run --rm --entrypoint sh "${API_TAG}" \
    -c 'test -f /app/config/initializers/999_unlock_premium.rb && echo "OK: initializer present"'
docker run --rm --entrypoint sh "${API_TAG}" \
    -c 'ruby -c /app/config/initializers/999_unlock_premium.rb'

echo
echo "=== Verifying FRONT nginx config ==="
docker run --rm "${FRONT_TAG}" nginx -t

echo
echo "Built:"
echo "  ${API_TAG}"
echo "  ${FRONT_TAG}"
echo
echo "Update compose x-backend-image to: ${API_TAG}"
echo "Update compose x-frontend-image to: ${FRONT_TAG}"
echo "Remove bind-mount for nginx-lago.conf (now baked into front image)"
