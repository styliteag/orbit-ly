defmodule Orbitly.Shortener.ClickEvent do
  @moduledoc """
  Raw click record (ADR-0005): full IP and user agent, kept for 12 months.

  Writes happen exclusively through `Orbitly.Shortener.ClickBuffer` via
  batched `Repo.insert_all` — there is deliberately no create action here,
  the hot path must not pay per-click Ash overhead. Reads go through Ash
  with owner/admin policies.
  """

  use Ash.Resource,
    otp_app: :orbitly,
    domain: Orbitly.Shortener,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "click_events"
    repo Orbitly.Repo

    references do
      reference :link, on_delete: :delete
    end
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:admin, true)
      authorize_if expr(link.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :ip, :string do
      public? true
    end

    attribute :user_agent, :string do
      public? true
    end

    attribute :referrer, :string do
      public? true
    end
  end

  relationships do
    belongs_to :link, Orbitly.Shortener.Link do
      allow_nil? false
      attribute_public? true
    end
  end
end
