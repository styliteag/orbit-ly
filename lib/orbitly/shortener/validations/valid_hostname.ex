defmodule Orbitly.Shortener.Validations.ValidHostname do
  @moduledoc """
  DNS-style hostname: labels of [a-z0-9-], not starting/ending with a dash,
  joined by dots. Single-label hosts (localhost) are allowed for development.
  Case-insensitive here — storage is downcased by NormalizeHostname.
  """

  use Ash.Resource.Validation

  @hostname ~r/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/i

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :hostname) do
      hostname = Ash.Changeset.get_attribute(changeset, :hostname)

      if is_binary(hostname) and Regex.match?(@hostname, String.trim(hostname)) do
        :ok
      else
        {:error, field: :hostname, message: "is not a valid hostname"}
      end
    else
      :ok
    end
  end
end
