defmodule Orbitly.Shortener.Changes.SetSlug do
  @moduledoc """
  Takes the user-provided slug argument or generates a free one.

  Generation retries on collision; a race between the existence check and
  the insert is still caught by the unique index on (domain_id, slug).
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Orbitly.Shortener.Slug

  @attempts 5

  @impl true
  def change(changeset, _opts, _context) do
    slug = Ash.Changeset.get_argument(changeset, :slug)

    cond do
      # `/`, `@`, `/*`, `*` → the domain root ("") or catch-all ("*")
      is_binary(slug) and not is_nil(Slug.special_slug(slug)) ->
        Ash.Changeset.force_change_attribute(changeset, :slug, Slug.special_slug(slug))

      is_binary(slug) and slug != "" ->
        Ash.Changeset.force_change_attribute(changeset, :slug, slug)

      true ->
        # generate only on actual execution — AshPhoenix.Form builds and
        # validates changesets long before submit
        Ash.Changeset.before_action(changeset, &generate/1)
    end
  end

  defp generate(changeset) do
    case Ash.Changeset.get_attribute(changeset, :domain_id) do
      nil ->
        # missing domain_id fails its own allow_nil? check
        changeset

      domain_id ->
        case find_free_slug(domain_id) do
          nil ->
            Ash.Changeset.add_error(changeset,
              field: :slug,
              message: "could not generate a free slug, please provide one"
            )

          slug ->
            Ash.Changeset.force_change_attribute(changeset, :slug, slug)
        end
    end
  end

  defp find_free_slug(domain_id) do
    Enum.find_value(1..@attempts, fn _ ->
      candidate = Slug.generate()
      if free?(domain_id, candidate), do: candidate
    end)
  end

  defp free?(domain_id, slug) do
    not (Orbitly.Shortener.Link
         |> Ash.Query.filter(domain_id == ^domain_id and slug == ^slug)
         |> Ash.exists?(authorize?: false))
  end
end
