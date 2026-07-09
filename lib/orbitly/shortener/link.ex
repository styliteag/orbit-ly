defmodule Orbitly.Shortener.Link do
  @moduledoc """
  Maps a slug on a domain to a target URL.

  Owned by exactly one user; slugs are unique per (domain, slug) across all
  users (ADR-0002/0003). Optional time-based expiry (expired links answer
  410, ADR "Ablauf") and optional password protection.
  """

  use Ash.Resource,
    otp_app: :orbitly,
    domain: Orbitly.Shortener,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Orbitly.Shortener.CacheInvalidator]

  sqlite do
    table "links"
    repo Orbitly.Repo

    references do
      reference :domain, on_delete: :delete
      reference :owner, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:target_url, :expires_at, :domain_id, :description]

      argument :slug, :string, allow_nil?: true
      argument :password, :string, allow_nil?: true, sensitive?: true

      change relate_actor(:owner)
      change Orbitly.Shortener.Changes.SetSlug
      change Orbitly.Shortener.Changes.HashLinkPassword
      validate Orbitly.Shortener.Validations.ValidSlug
      validate Orbitly.Shortener.Validations.ValidTargetUrl
    end

    update :update do
      accept [:target_url, :expires_at, :description]

      argument :password, :string, allow_nil?: true, sensitive?: true

      require_atomic? false
      change Orbitly.Shortener.Changes.HashLinkPassword
      validate Orbitly.Shortener.Validations.ValidTargetUrl
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :target_url, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
      constraints max_length: 500
    end

    attribute :expires_at, :utc_datetime do
      public? true
    end

    attribute :password_hash, :string do
      sensitive? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :domain, Orbitly.Shortener.Domain do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :owner, Orbitly.Accounts.User do
      allow_nil? false
    end

    has_many :click_events, Orbitly.Shortener.ClickEvent
  end

  identities do
    identity :unique_slug_per_domain, [:domain_id, :slug]
  end
end
