defmodule Orbitly.Shortener.Validations.ValidTargetUrl do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :target_url) do
      case URI.new(Ash.Changeset.get_attribute(changeset, :target_url) || "") do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          :ok

        _ ->
          {:error, field: :target_url, message: "must be a valid http(s) URL"}
      end
    else
      :ok
    end
  end
end
