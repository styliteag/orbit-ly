defmodule Mix.Tasks.Orbitly.ImportKutt do
  @shortdoc "Import links from a Kutt instance via its API"

  @moduledoc """
  Imports links from a running Kutt instance into orbit-ly.

      mix orbitly.import_kutt --api-url http://localhost:3000 --api-key KEY [--domain host]

  All links are assigned to the current admin and placed on the primary domain
  (or `--domain`). See `Orbitly.KuttImport` for the mapping and caveats
  (synthesised clicks, dropped link passwords). For a production release use the
  `bin/import_kutt` wrapper instead — a release has no Mix.
  """

  use Mix.Task

  @impl true
  def run(argv) do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv, strict: [api_url: :string, api_key: :string, domain: :string])

    api_url = opts[:api_url] || raise "--api-url is required"
    api_key = opts[:api_key] || raise "--api-key is required"

    Mix.Task.run("app.start")

    Orbitly.KuttImport.run(
      client: Orbitly.KuttImport.ApiClient,
      config: %{api_url: String.trim_trailing(api_url, "/"), api_key: api_key},
      domain: opts[:domain]
    )
    |> Orbitly.KuttImport.Report.print()
  end
end
