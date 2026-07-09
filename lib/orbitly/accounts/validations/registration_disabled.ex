defmodule Orbitly.Accounts.Validations.RegistrationDisabled do
  @moduledoc """
  Hard-disables open registration (ADR-0006). The register action must keep
  existing (the password strategy requires it), so it always fails instead —
  this also covers the /auth POST endpoint, which bypasses normal policies
  as an AshAuthentication interaction. Accounts are created by the instance
  admin via :admin_create.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(_changeset, _opts, _context) do
    {:error, field: :email, message: "open registration is disabled on this instance"}
  end
end
