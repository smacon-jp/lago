#!/usr/bin/env bash
# Build the premium-unlocked lago-api image.
#
# Usage:
#   ./scripts/build-premium.sh                # defaults to v1.45.1
#   ./scripts/build-premium.sh v1.46.0        # override upstream version
#
# Run from the repo root (it uses the repo dir as build context).

set -euo pipefail

LAGO_VERSION="${1:-v1.45.1}"
IMAGE_TAG="lago-api-premium:${LAGO_VERSION}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Building ${IMAGE_TAG} from getlago/api:${LAGO_VERSION} ==="
docker build \
    --build-arg "LAGO_VERSION=${LAGO_VERSION}" \
    --file "${REPO_ROOT}/Dockerfile.api-premium" \
    --tag "${IMAGE_TAG}" \
    "${REPO_ROOT}"

echo
echo "=== Verifying initializer present in image ==="
docker run --rm --entrypoint sh "${IMAGE_TAG}" \
    -c 'test -f /app/config/initializers/999_unlock_premium.rb && echo OK: initializer present'

echo
echo "=== Verifying Ruby can parse initializer inside image ==="
docker run --rm --entrypoint sh "${IMAGE_TAG}" \
    -c 'ruby -c /app/config/initializers/999_unlock_premium.rb'

echo
echo "Built: ${IMAGE_TAG}"
echo "Point your docker-compose api/worker/clock services at this tag."
