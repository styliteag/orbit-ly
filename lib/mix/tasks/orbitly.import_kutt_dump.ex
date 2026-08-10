defmodule Mix.Tasks.Orbitly.ImportKuttDump do
  @shortdoc "Import links and real click history from a Kutt pg_dump"

  @moduledoc """
  Rebuilds links and click history from a `pg_dump` of a Kutt database
  (plain or gzipped):

      mix orbitly.import_kutt_dump --file dump.sql.gz [--owner user@example.com] [--reset]

  Unlike `mix orbitly.import_kutt` (HTTP API, aggregate visit counts only,
  synthesized history), the dump carries a `visits` row per link and hour, so
  clicks keep their real time, referrer and browser. `--reset` deletes every
  existing link and click event first — the usual choice for a one-off
  migration. See `Orbitly.KuttDump.Importer` for the retention rule.
  """

  use Mix.Task

  @impl true
  def run(argv) do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [file: :string, owner: :string, reset: :boolean]
      )

    file = opts[:file] || raise "--file is required"

    Mix.Task.run("app.start")

    file
    |> Orbitly.KuttDump.parse()
    |> Orbitly.KuttDump.Importer.run(owner: opts[:owner], reset: opts[:reset] || false)
    |> print()
  end

  defp print(report) do
    if report.deleted_links > 0 or report.deleted_events > 0 do
      Mix.shell().info(
        "reset: deleted #{report.deleted_links} links and #{report.deleted_events} click events"
      )
    end

    Mix.shell().info("imported #{report.links} links, #{report.events} click events")

    unless report.domains == [] do
      Mix.shell().info("created domains: #{Enum.join(report.domains, ", ")}")
    end

    unless report.renamed_links == [] do
      renamed = Enum.map_join(report.renamed_links, ", ", fn {from, to} -> "#{from} -> #{to}" end)
      Mix.shell().info("renamed (reserved or taken): #{renamed}")
    end

    unless report.unknown_owners == [] do
      Mix.shell().info(
        "no account here for: #{Enum.join(report.unknown_owners, ", ")} — their links went to the fallback owner"
      )
    end

    unless report.skipped_links == [] do
      Mix.shell().info("skipped (invalid slug): #{Enum.join(report.skipped_links, ", ")}")
    end

    if report.dropped_by_retention > 0 do
      Mix.shell().info(
        "dropped #{report.dropped_by_retention} clicks older than the 12-month retention window"
      )
    end
  end
end
