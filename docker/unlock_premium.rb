# frozen_string_literal: true

# Premium feature unlock for self-hosted Lago (AGPL fork).
#
# Removes both license gate layers:
#
#   Layer 1 — LagoUtils::License#premium?
#     Global flag that gates most premium features. Forced to true.
#
#   Layer 2 — Organization#<integration>_enabled?
#     Per-org instance methods that combine License.premium? with a DB
#     column check (premium_integrations varchar[]). Both parts are addressed:
#       a) Each method forced to return true (instance-level API)
#       b) The DB column is backfilled and kept populated (SQL-scope API)
#
# Why the DB column also matters:
#   Organization model defines scopes like:
#     scope :with_netsuite_support, -> { where("? = ANY(premium_integrations)", "netsuite") }
#   Background jobs and analytics queries use these scopes directly against
#   the database — they bypass the instance method override. Without backfill,
#   those jobs silently skip every org even though the UI shows features active.
#
# Upstream-update robustness:
#   Raises at boot if LagoUtils::License, Organization, or
#   Organization::PREMIUM_INTEGRATIONS are missing, giving a loud signal on
#   version bumps instead of silently reverting to locked behavior.

ALL_INTEGRATIONS_SQL = Organization::PREMIUM_INTEGRATIONS.map { |i| "'#{i}'" }.join(",") if defined?(Organization::PREMIUM_INTEGRATIONS)

Rails.application.config.after_initialize do
  # --- safety guards --------------------------------------------------------
  raise "[premium-unlock] LagoUtils::License missing" unless defined?(LagoUtils::License)
  raise "[premium-unlock] Organization model missing" unless defined?(Organization)
  raise "[premium-unlock] Organization::PREMIUM_INTEGRATIONS missing" unless defined?(Organization::PREMIUM_INTEGRATIONS)

  all_integrations = Organization::PREMIUM_INTEGRATIONS
  integrations_sql  = all_integrations.map { |i| "'#{i}'" }.join(",")

  # --- Layer 1: global license always premium --------------------------------
  LagoUtils::License.class_eval do
    define_method(:premium?) { true }
    define_method(:verify)   { @premium = true }
  end

  # --- Layer 2a: instance method override ------------------------------------
  Organization.class_eval do
    all_integrations.each do |pi|
      define_method("#{pi}_enabled?") { true }
    end
  end

  # --- Layer 2b: DB column backfill (makes SQL scopes work) ------------------
  # Runs in a background thread so a slow DB on boot doesn't block puma/sidekiq.
  # Retries with back-off in case the DB isn't fully ready yet.
  Thread.new do
    retries = 0
    begin
      sql = <<~SQL
        UPDATE organizations
        SET    premium_integrations = ARRAY[#{integrations_sql}]::varchar[]
        WHERE  NOT (premium_integrations @> ARRAY[#{integrations_sql}]::varchar[])
      SQL
      rows = ApplicationRecord.connection.execute(sql).cmd_tuples
      Rails.logger.info "[premium-unlock] DB backfill: #{rows} org(s) updated"
    rescue => e
      if retries < 5
        retries += 1
        sleep(retries * 2)
        retry
      end
      Rails.logger.error "[premium-unlock] DB backfill failed after #{retries} retries: #{e.message}"
    end
  end

  # --- Layer 2c: auto-populate premium_integrations for newly created orgs ---
  Organization.after_create_commit do
    update_columns(premium_integrations: Organization::PREMIUM_INTEGRATIONS)
  end

  Rails.logger.info(
    "[premium-unlock] License.premium? forced true | " \
    "#{all_integrations.size} integration methods overridden | " \
    "DB backfill running in background"
  )
end
