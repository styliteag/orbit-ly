defmodule Orbitly.Accounts.UserNotifier do
  @moduledoc "Transactional account emails (password reset) via Swoosh."

  import Swoosh.Email

  alias Orbitly.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"orbit-ly", "noreply@example.com"})
      |> subject(subject)
      |> html_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Password reset instructions with a link carrying the reset token."
  def deliver_reset_password_instructions(user, url) do
    deliver(to_string(user.email), "Reset your password", """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    <p>If you did not request this, ignore this email.</p>
    """)
  end
end
