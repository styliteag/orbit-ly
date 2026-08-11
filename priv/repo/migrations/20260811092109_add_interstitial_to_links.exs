defmodule Orbitly.Repo.Migrations.AddInterstitialToLinks do
  use Ecto.Migration

  # Per-link opt-in for the preview (interstitial) redirect: the hot path renders
  # a transparent "continue" page instead of a bare 302, so a security appliance
  # sees plain HTML with nothing to auto-follow.
  def change do
    alter table(:links) do
      add :interstitial, :boolean, null: false, default: false
    end
  end
end
