defmodule Orbitly.Repo.Migrations.AddAliasOfToDomains do
  use Ecto.Migration

  # A domain can be an alias of another one: it owns no links itself, every
  # slug of the target resolves on the alias host too. Deleting the target
  # leaves the alias behind as a plain (empty) domain.
  def change do
    alter table(:domains) do
      add :alias_of_id, references(:domains, type: :uuid, on_delete: :nilify_all)
    end

    create index(:domains, [:alias_of_id])
  end
end
