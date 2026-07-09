defmodule Orbitly.Shortener.Changes.UnsetOtherPrimaries do
  @moduledoc """
  Keeps the invariant "exactly one primary domain": after making a domain
  primary, all other domains lose the flag — in the same transaction.
  """

  use Ash.Resource.Change

  import Ecto.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, domain ->
      Orbitly.Repo.update_all(
        from(d in Orbitly.Shortener.Domain, where: d.id != ^domain.id),
        set: [is_primary: false]
      )

      {:ok, domain}
    end)
  end
end
