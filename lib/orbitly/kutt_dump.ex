defmodule Orbitly.KuttDump do
  @moduledoc """
  Reads a `pg_dump` of a Kutt database (plain or gzipped) and returns its
  `links`, `visits` and `domains` rows.

  Why a dump and not the API (`Orbitly.KuttImport`): Kutt's HTTP API exposes
  only a link's total `visit_count`, which forces the importer to *invent* a
  click history spread evenly over the link's lifetime. The database keeps a
  `visits` row per link and hour with the real timestamp, browser counters and
  referrers — everything needed to reconstruct a truthful history.

  Only `COPY … FROM stdin` blocks are read; nothing in the dump is executed.
  """

  @tables ~w(links visits domains users)

  @doc "Parses the dump at `path` into `%{\"links\" => [row], …}` (string keys)."
  def parse(path) do
    path
    |> read()
    # Dumps that travelled through a Windows share or an editor arrive with
    # CRLF; a trailing \r would break both the COPY header match and the last
    # column of every row.
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> collect(nil, %{})
  end

  defp read(path) do
    contents = File.read!(path)

    if String.ends_with?(path, ".gz"), do: :zlib.gunzip(contents), else: contents
  end

  # Walks the dump once, collecting the rows of the COPY blocks we care about.
  defp collect([], _current, acc), do: acc

  defp collect([line | rest], nil, acc) do
    case copy_header(line) do
      {table, columns} -> collect(rest, {table, columns}, Map.put_new(acc, table, []))
      nil -> collect(rest, nil, acc)
    end
  end

  defp collect(["\\." | rest], _current, acc), do: collect(rest, nil, acc)

  defp collect([line | rest], {table, columns}, acc) do
    row = columns |> Enum.zip(fields(line)) |> Map.new()
    collect(rest, {table, columns}, Map.update!(acc, table, &[row | &1]))
  end

  defp copy_header(line) do
    with ["COPY public." <> table_and_columns, "FROM stdin;"] <-
           String.split(line, ") ", parts: 2),
         [table, columns] <- String.split(table_and_columns, " (", parts: 2),
         true <- table in @tables do
      {table, String.split(columns, ", ")}
    else
      _ -> nil
    end
  end

  # COPY text format: tab separated, \N is NULL, backslash escapes for control
  # characters (a literal tab inside a value would otherwise break the row).
  defp fields(line) do
    line
    |> String.split("\t")
    |> Enum.map(fn
      "\\N" -> nil
      field -> unescape(field)
    end)
  end

  defp unescape(field) do
    field
    |> String.replace("\\t", "\t")
    |> String.replace("\\n", "\n")
    |> String.replace("\\r", "\r")
    |> String.replace("\\\\", "\\")
  end

  @doc "Rows of one table, oldest first (the dump order)."
  def rows(parsed, table), do: parsed |> Map.get(table, []) |> Enum.reverse()

  @doc "Integer field, `nil` for NULL."
  def int(nil), do: nil
  def int(value), do: value |> String.trim() |> String.to_integer()

  @doc """
  Timestamp field as a `DateTime`, `nil` for NULL. Always at microsecond
  precision — the click and link timestamp columns are `:utc_datetime_usec`
  and Ecto rejects anything coarser.
  """
  def datetime(nil), do: nil

  def datetime(value) do
    # "2026-08-10 19:41:02.435298+00" — ISO 8601 apart from the space.
    case value |> String.replace(" ", "T") |> DateTime.from_iso8601() do
      {:ok, datetime, _offset} -> usec(datetime)
      _ -> nil
    end
  end

  defp usec(%DateTime{microsecond: {value, _precision}} = datetime),
    do: %{datetime | microsecond: {value, 6}}

  @doc """
  Kutt stores referrer hostnames with `.` replaced by `[dot]` and counts them
  per visit bucket; `direct` means no referrer.
  """
  def referrers(nil), do: %{}

  def referrers(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> Map.new(map, fn {key, count} -> {referrer(key), count} end)
      _ -> %{}
    end
  end

  defp referrer("direct"), do: nil
  defp referrer(host), do: String.replace(host, "[dot]", ".")
end
