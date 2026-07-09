defmodule Orbitly.Shortener.Changes.HashLinkPassword do
  @moduledoc """
  Hashes the optional link password argument into password_hash.
  An empty string removes the protection.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :password) do
      nil ->
        changeset

      "" ->
        Ash.Changeset.force_change_attribute(changeset, :password_hash, nil)

      password when is_binary(password) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :password_hash,
          Bcrypt.hash_pwd_salt(password)
        )
    end
  end
end
