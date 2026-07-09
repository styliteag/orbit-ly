defmodule Orbitly.Shortener.Changes.NormalizeHostname do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :hostname) do
      hostname when is_binary(hostname) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :hostname,
          hostname |> String.trim() |> String.downcase()
        )

      _ ->
        changeset
    end
  end
end
