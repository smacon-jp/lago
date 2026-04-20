#!/usr/bin/env bash
# Runtime smoke-test for the premium unlock against a running lago-api
# container. Boots a Rails runner inside the target container and asserts that
# License.premium? and every Organization<integration>_enabled? now return true.
#
# Usage:
#   ./scripts/verify-premium.sh             # targets container named "lago-api"
#   ./scripts/verify-premium.sh my-api      # custom container name
#
# If run remotely, prefix with SSH:
#   ssh smacon-dev "bash -s" < scripts/verify-premium.sh lago-api

set -euo pipefail

CONTAINER="${1:-lago-api}"

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "FAIL: container '${CONTAINER}' not running" >&2
    exit 1
fi

echo "=== Checking License.premium? inside ${CONTAINER} ==="
docker exec "${CONTAINER}" bundle exec rails runner '
  raise "License constant missing" unless defined?(License)
  raise "License.premium? returned false — unlock not active" unless License.premium?
  puts "OK: License.premium? => true"
'

echo
echo "=== Checking every Organization::PREMIUM_INTEGRATIONS toggle ==="
docker exec "${CONTAINER}" bundle exec rails runner '
  org = Organization.new
  locked = Organization::PREMIUM_INTEGRATIONS.reject { |pi| org.public_send("#{pi}_enabled?") }
  if locked.any?
    abort "FAIL: still locked: #{locked.join(", ")}"
  end
  puts "OK: all #{Organization::PREMIUM_INTEGRATIONS.size} integrations enabled"
'

echo
echo "All premium unlock checks passed."
