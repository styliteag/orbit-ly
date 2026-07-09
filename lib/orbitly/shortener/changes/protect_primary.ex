defmodule Orbitly.Shortener.Changes.ProtectPrimary do
  @moduledoc """
  Guards the sentinel primary domain: it cannot be destroyed nor deactivated
  through the admin actions. Its hostname still follows MAIN_DOMAIN via
  `Orbitly.Shortener.PrimaryDomain` (which renames in place, active unchanged),
  so that path is deliberately left open. Redirect domains are untouched.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.data.is_primary, do: guard(changeset), else: changeset
  end

  defp guard(%{action_type: :destroy} = changeset) do
    Ash.Changeset.add_error(changeset,
      field: :is_primary,
      message: "the primary domain cannot be deleted"
    )
  end

  defp guard(%{action_type: :update} = changeset) do
    if Ash.Changeset.get_attribute(changeset, :active) == false do
      Ash.Changeset.add_error(changeset,
        field: :active,
        message: "the primary domain cannot be deactivated"
      )
    else
      changeset
    end
  end
end
