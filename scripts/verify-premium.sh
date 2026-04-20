#!/usr/bin/env bash
# Runtime smoke-test for all premium unlock patches against live containers.
#
# Usage:
#   ./scripts/verify-premium.sh                     # default container names
#   ./scripts/verify-premium.sh lago-api lago-front  # custom names
#
# Remote:
#   ssh smacon-dev "bash -s" < scripts/verify-premium.sh

set -euo pipefail

API_CONTAINER="${1:-lago-api}"
FRONT_CONTAINER="${2:-lago-front}"
PASS=0
FAIL=0

ok()   { echo "  OK: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }

# ---- API: License.premium? ----
echo "=== [API] License.premium? ==="
if docker ps --format '{{.Names}}' | grep -qx "${API_CONTAINER}"; then
  result=$(docker exec "${API_CONTAINER}" bundle exec rails runner \
    'puts License.premium? ? "true" : "false"' 2>/dev/null | tail -1)
  [ "$result" = "true" ] && ok "License.premium? => true" || fail "License.premium? => ${result}"
else
  fail "container '${API_CONTAINER}' not running"
fi

# ---- API: all integration methods ----
echo
echo "=== [API] Organization integration methods ==="
docker exec "${API_CONTAINER}" bundle exec rails runner '
  org = Organization.new
  locked = Organization::PREMIUM_INTEGRATIONS.reject { |pi| org.public_send("#{pi}_enabled?") }
  if locked.any?
    abort "still locked: #{locked.join(", ")}"
  end
  puts "all #{Organization::PREMIUM_INTEGRATIONS.size} integrations enabled"
' 2>/dev/null | grep -v "Sidekiq\|premium-unlock" | tail -1 | while read line; do
  [[ "$line" == *"all"* ]] && ok "$line" || fail "$line"
done

# ---- API: DB column backfill ----
echo
echo "=== [API] DB premium_integrations column ==="
docker exec "${API_CONTAINER}" bundle exec rails runner '
  total   = Organization.count
  backfilled = Organization.where("array_length(premium_integrations, 1) = ?",
                                  Organization::PREMIUM_INTEGRATIONS.size).count
  puts "#{backfilled}/#{total} orgs fully backfilled"
  abort "#{total - backfilled} org(s) not fully backfilled" if backfilled < total
' 2>/dev/null | grep -v "Sidekiq\|premium-unlock" | tail -1 | while read line; do
  [[ "$line" == *"/"* ]] && ok "$line" || fail "$line"
done

# ---- FRONT: nginx resolver config ----
echo
echo "=== [FRONT] nginx resolver directive ==="
if docker ps --format '{{.Names}}' | grep -qx "${FRONT_CONTAINER}"; then
  if docker exec "${FRONT_CONTAINER}" grep -q "resolver 127.0.0.11" /etc/nginx/conf.d/default.conf; then
    ok "resolver 127.0.0.11 present"
  else
    fail "resolver directive missing from nginx config"
  fi

  if docker exec "${FRONT_CONTAINER}" grep -q 'set \$lago_api_upstream' /etc/nginx/conf.d/default.conf; then
    ok 'set $lago_api_upstream variable present (forces DNS re-resolution)'
  else
    fail 'set $lago_api_upstream missing — nginx will cache upstream IP'
  fi
else
  fail "container '${FRONT_CONTAINER}' not running"
fi

# ---- FRONT: nginx syntax ----
echo
echo "=== [FRONT] nginx config syntax ==="
docker exec "${FRONT_CONTAINER}" nginx -t 2>&1 | grep -E "OK|error" | while read line; do
  [[ "$line" == *"OK"* ]] && ok "$line" || fail "$line"
done

# ---- summary ----
echo
echo "=============================="
echo "PASS: ${PASS}  FAIL: ${FAIL}"
echo "=============================="
[ "${FAIL}" -eq 0 ]
