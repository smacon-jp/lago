# Premium Feature Unlock (self-hosted Lago)

This fork ships a build-time overlay that removes the license gates from the
open-source lago-api image, so every premium feature and premium integration
is usable on a self-hosted deployment.

## What gets unlocked

### Layer 1 — global `License.premium?`
Source of the gate: `api/lib/lago_utils/lago_utils/license.rb`
Flips to `true` unconditionally. Enables:
- Analytics: MRR, invoiced usages, invoice collections
- Pricing units (multi-currency)
- Billing entities (multi-org)
- Commitments override
- Usage-monitoring alerts
- Graduated-percentage charges
- Multi billing-entity invoice settings
- Everything behind the `PremiumFeatureOnly` controller concern

### Layer 2 — per-org `<integration>_enabled?`
Source of the gate: `api/app/models/organization.rb` (`PREMIUM_INTEGRATIONS`)
Every toggle returns `true`, covering these 27 integrations:

```
beta_payment_authorization, netsuite, okta, avalara, xero,
progressive_billing, lifetime_usage, hubspot, auto_dunning,
revenue_analytics, salesforce, api_permissions, revenue_share,
remove_branding_watermark, manual_payments, from_email, issue_receipts,
preview, multi_entities_pro, multi_entities_enterprise,
analytics_dashboards, forecasted_usage, projected_usage, custom_roles,
events_targeting_wallets, security_logs, granular_lifetime_usage
```

### Frontend
The front bundle reads `currentUser.premium` and `organization.<integration>_enabled?`
over GraphQL. Both trace back to the two layers above, so no front-end patch is
needed — the stock `getlago/front` image renders every premium UI once the API
returns `true`.

## How it's wired

- [docker/unlock_premium.rb](../docker/unlock_premium.rb) — Rails initializer
  that monkey-patches `LagoUtils::License` and `Organization` in
  `after_initialize`. No upstream source files are edited.
- [Dockerfile.api-premium](../Dockerfile.api-premium) — `FROM getlago/api:${LAGO_VERSION}`
  then copies the initializer into `/app/config/initializers/999_unlock_premium.rb`
  (prefix `999_` ensures it runs last).
- [scripts/build-premium.sh](../scripts/build-premium.sh) — builds
  `lago-api-premium:${LAGO_VERSION}` and sanity-checks the image.
- [scripts/verify-premium.sh](../scripts/verify-premium.sh) — boots a Rails
  runner inside the live container and asserts the unlocks are active.

## Surviving upstream updates

The initializer depends on three upstream symbols:

1. `LagoUtils::License` class
2. `Organization` model
3. `Organization::PREMIUM_INTEGRATIONS` constant

If any of them is renamed or removed in a future Lago release, the initializer
raises at boot — `rails` exits non-zero, the container health check fails, the
old container stays up in its restart loop, and you notice immediately. At that
point, update `unlock_premium.rb` to match the new structure and rebuild.

To bump versions safely:

```bash
# 1. bump the pinned submodules if you also want to audit upstream source diffs
git submodule update --remote api front

# 2. build the new image
./scripts/build-premium.sh v1.46.0

# 3. point docker-compose at lago-api-premium:v1.46.0 for api, worker, clock

# 4. verify after restart
./scripts/verify-premium.sh lago-api
```

## Deployment (smacon-dev via Dokploy)

1. Build the image on the target host:
   ```bash
   ssh smacon-dev
   git clone https://github.com/smacon-jp/lago.git /opt/lago-fork
   cd /opt/lago-fork
   ./scripts/build-premium.sh v1.45.1
   ```
2. In the Dokploy UI for the `monitoring-billing-kjuuru` compose project,
   change these three `image:` values:
   ```yaml
   x-backend-image: &a3
     image: lago-api-premium:v1.45.1    # was: getlago/api:v1.45.1
   ```
   (This anchor is used by the `api`, `api-worker`, `api-clock`, and `migrate`
   services — one change covers them all.)
3. Redeploy from Dokploy. The new containers will log
   `[premium-unlock] all 27 premium integrations + License.premium? forced true`
   on boot.
4. Run `./scripts/verify-premium.sh` to confirm.

## License / ethics

Lago API and Lago Front are AGPL-3.0. AGPL permits private modification and use
(including disabling license checks in your own fork). If you ever redistribute
the modified binary or expose it as a hosted service to third parties, AGPL
requires you to publish the source of the modifications — that's already
covered by this fork being a public GitHub repository. Do not remove the
upstream Lago copyright/licence notices.
