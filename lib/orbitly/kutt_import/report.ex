defmodule Orbitly.KuttImport.Report do
  @moduledoc """
  Human-readable printing of an `Orbitly.KuttImport.run/1` result. Uses
  `IO.puts` so it works both under Mix and inside a release (`bin/import_kutt`).
  """

  def print(report) do
    IO.puts("""

    Kutt import finished:
      imported:        #{length(report.imported)}
      renamed (slug):  #{length(report.renamed)}
      skipped (exists):#{length(report.skipped_exists)}
      skipped (slug):  #{length(report.skipped_invalid)}
      clicks synthesised: #{report.clicks}
    """)

    list("Renamed (reserved slug got a suffix)", report.renamed, fn {from, to} ->
      "  #{from} → #{to}"
    end)

    list("Imported WITHOUT password (reset these)", report.protected, &"  #{&1}")
    list("Skipped — invalid slug", report.skipped_invalid, &"  #{&1}")
    list("Skipped — slug already on domain", report.skipped_exists, &"  #{&1}")

    report
  end

  defp list(_title, [], _fmt), do: :ok

  defp list(title, entries, fmt) do
    IO.puts(title <> ":")
    Enum.each(entries, fn entry -> IO.puts(fmt.(entry)) end)
    IO.puts("")
  end
end
