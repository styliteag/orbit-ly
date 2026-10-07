defmodule Orbitly.Repo.Migrations.AddUserDomainAccess do
  use Ecto.Migration

  # Per-user domain access: `all_domains` (default on) lets a user use every
  # domain; when an admin switches it off, only the domains in `user_domains`
  # are usable. `default_domain_id` is the user's preselected domain for new
  # links. Admins are never restricted.
  def change do
    alter table(:users) do
      add :all_domains, :boolean, null: false, default: true
      add :default_domain_id, references(:domains, type: :uuid, on_delete: :nilify_all)
    end

    create table(:user_domains, primary_key: false) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :domain_id, references(:domains, type: :uuid, on_delete: :delete_all), null: false
    end

    create unique_index(:user_domains, [:user_id, :domain_id])
    create index(:user_domains, [:domain_id])
  end
end
