defmodule Orbitly.Accounts.UserToken do
  @moduledoc """
  Opaque, hashed tokens for sessions and password resets (plain Phoenix, the
  phx.gen.auth model). Session tokens are stored raw; email (reset) tokens are
  stored hashed and handed out url-encoded, so a DB leak cannot mint valid
  reset links.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Orbitly.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # Reset tokens are short-lived; sessions last two months.
  @reset_password_validity_in_days 1
  @session_validity_in_days 60

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Orbitly.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Builds a raw session token and its DB record."
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc "Query returning the user for a valid, unexpired session token."
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds an email token: the url-encoded raw token is handed to the user, its
  SHA-256 hash is stored. `context` is e.g. "reset_password".
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{token: hashed_token, context: context, sent_to: sent_to, user_id: user.id}}
  end

  @doc "Query returning the user for a valid, unexpired email token."
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day"),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
