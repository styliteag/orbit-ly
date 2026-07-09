defmodule Orbitly.Shortener.CacheInvalidator do
  @moduledoc """
  Flushes the redirect cache on any Domain/Link mutation. A full flush is
  deliberately coarse: correct, trivial, and cheap at our load profile
  (ADR-0008) — entries repopulate on the next lookup.
  """

  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{}) do
    Orbitly.Shortener.RedirectCache.flush()
    :ok
  end
end
