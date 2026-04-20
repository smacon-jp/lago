# frozen_string_literal: true

# Premium feature unlock for self-hosted Lago (AGPL fork).
#
# Overrides the two license gates in lago-api so all premium features are
# enabled without a Lago Cloud license key:
#
#   1. LagoUtils::License#premium?  - global "is this a paid cloud tenant?" flag
#   2. Organization#<integration>_enabled?  - per-org premium integration toggles
#
# This file is copied into /app/config/initializers/ at image build time by
# Dockerfile.api-premium. It runs after Rails eager-loads all app classes, so
# both the License singleton (see config/initializers/license.rb) and the
# Organization model already exist when this executes.
#
# Upstream-update robustness:
#   - Uses class_eval + define_method against named constants
#     (LagoUtils::License, Organization, Organization::PREMIUM_INTEGRATIONS)
#   - Fails loudly if any of those constants go missing on a future upstream
#     bump, so the image build or boot errors instead of silently reverting to
#     the locked behavior.

Rails.application.config.after_initialize do
  raise "Premium unlock: LagoUtils::License missing" unless defined?(LagoUtils::License)
  raise "Premium unlock: Organization model missing" unless defined?(Organization)
  raise "Premium unlock: Organization::PREMIUM_INTEGRATIONS missing" unless defined?(Organization::PREMIUM_INTEGRATIONS)

  # Layer 1: global license always premium.
  LagoUtils::License.class_eval do
    define_method(:premium?) { true }
    define_method(:verify)   { @premium = true }
  end

  # Layer 2: every per-org <integration>_enabled? returns true.
  Organization.class_eval do
    Organization::PREMIUM_INTEGRATIONS.each do |premium_integration|
      define_method("#{premium_integration}_enabled?") { true }
    end
  end

  Rails.logger.info(
    "[premium-unlock] all #{Organization::PREMIUM_INTEGRATIONS.size} premium integrations + " \
    "License.premium? forced true"
  )
end
