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
    defaults [:read, :destroy]

    create :create do
      accept [:hostname, :is_primary, :active]
      change Orbitly.Shortener.Changes.NormalizeHostname
    end

    update :update do
      accept [:hostname, :active]
      require_atomic? false
      change Orbitly.Shortener.Changes.NormalizeHostname
    end

    update :make_primary do
      accept []
      require_atomic? false
      change set_attribute(:is_primary, true)
      change Orbitly.Shortener.Changes.UnsetOtherPrimaries
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
