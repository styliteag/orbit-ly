defmodule Orbitly.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Orbitly.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:orbitly, :token_signing_secret)
  end
end
