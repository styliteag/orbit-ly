defmodule Orbitly.Shortener.Domain do
  @moduledoc """
  A concrete hostname links can live under (ADR-0003).

  Admin-managed and shared by all users. The wildcard at the reverse proxy
  is infrastructure only — the application only knows concrete hostnames.
  Exactly one domain is primary and serves the dashboard UI (ADR-0004).
  """

  use Ash.Resource,
    otp_app: :orbitly,
    domain: Orbitly.Shortener,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Orbitly.Shortener.CacheInvalidator]

  sqlite do
    table "domains"
    repo Orbitly.Repo
  end

  actions do
    defaults [:read]

    # is_primary is intentionally NOT accepted: the primary is the env-driven
    # sentinel row managed by Orbitly.Shortener.PrimaryDomain, so admins can
    # only create plain redirect domains here.
    create :create do
      accept [:hostname, :active]
      change Orbitly.Shortener.Changes.NormalizeHostname
    end

    update :update do
      accept [:hostname, :active]
      require_atomic? false
      change Orbitly.Shortener.Changes.NormalizeHostname
      # The primary must stay reachable — never let it be deactivated here.
      change Orbitly.Shortener.Changes.ProtectPrimary
    end

    # The primary is managed via MAIN_DOMAIN, and deleting it would orphan its
    # links and take down the dashboard host.
    destroy :destroy do
      primary? true
      require_atomic? false
      change Orbitly.Shortener.Changes.ProtectPrimary
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  validations do
    validate Orbitly.Shortener.Validations.ValidHostname
  end

  attributes do
    uuid_primary_key :id

    attribute :hostname, :string do
      allow_nil? false
      public? true
    end

    attribute :is_primary, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_hostname, [:hostname]
  end
end
