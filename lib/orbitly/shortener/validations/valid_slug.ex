defmodule Orbitly.Shortener.Validations.ValidSlug do
  use Ash.Resource.Validation

  alias Orbitly.Shortener.Slug

  @impl true
  def validate(changeset, _opts, _context) do
    slug = Ash.Changeset.get_attribute(changeset, :slug)

    cond do
      # nil: a slug will be generated in before_action (always valid)
      is_nil(slug) ->
        :ok

      not Slug.valid_format?(slug) ->
        {:error,
         field: :slug, message: "must be 1-64 characters of letters, digits, dash or underscore"}

      Slug.reserved?(slug) ->
        {:error, field: :slug, message: "is reserved"}

      true ->
        :ok
    end
  end
end
