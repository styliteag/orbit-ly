defmodule Orbitly.Shortener.ClickStats do
  @moduledoc """
  Per-link click statistics as plain Ecto group-by queries (AshSqlite has no
  aggregates). Callers must have authorized the link via Ash beforehand —
  these functions take a bare, already-authorized link id.
  """

  import Ecto.Query

  alias Orbitly.Repo
  alias Orbitly.Shortener.ClickEvent

  def total(link_id) do
    Repo.aggregate(from(c in ClickEvent, where: c.link_id == ^link_id), :count)
  end

  @doc "Daily counts for the trailing `days` days, gaps filled with 0."
  def per_day(link_id, days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    counts =
      Repo.all(
        from(c in ClickEvent,
          where: c.link_id == ^link_id and c.occurred_at >= ^cutoff,
          group_by: fragment("date(?)", c.occurred_at),
          select: {fragment("date(?)", c.occurred_at), count(c.id)}
        )
      )
      |> Map.new()

    today = Date.utc_today()

    for offset <- (days - 1)..0//-1 do
      date = Date.add(today, -offset)
      {date, Map.get(counts, Date.to_iso8601(date), 0)}
    end
  end

  @ranges ~w(30d 90d 12m all)
  @default_range "12m"

  @doc "Selectable chart ranges, in display order."
  def ranges, do: @ranges

  def default_range, do: @default_range

  @doc """
  Click counts bucketed for a chart: daily for the short ranges, monthly for a
  year and for all time. Gaps are filled with zero so the x axis is continuous,
  and month buckets are keyed by their first day. Takes one already-authorized
  link id or a list of them.
  """
  def per_bucket(link_ids, range \\ @default_range)

  def per_bucket(link_id, range) when is_binary(link_id), do: per_bucket([link_id], range)

  def per_bucket(link_ids, range) when is_list(link_ids) do
    case window(link_ids, range) do
      {:day, from, to} -> %{granularity: :day, points: daily(link_ids, from, to)}
      {:month, from, to} -> %{granularity: :month, points: monthly(link_ids, from, to)}
    end
  end

  defp window(_link_ids, "30d"), do: {:day, Date.add(Date.utc_today(), -29), Date.utc_today()}
  defp window(_link_ids, "90d"), do: {:day, Date.add(Date.utc_today(), -89), Date.utc_today()}

  defp window(link_ids, "all") do
    today = Date.utc_today()

    from =
      case first_click_date(link_ids) do
        nil -> Date.shift(today, month: -11)
        date -> date
      end

    {:month, Date.beginning_of_month(from), today}
  end

  defp window(_link_ids, _twelve_months) do
    today = Date.utc_today()
    {:month, today |> Date.shift(month: -11) |> Date.beginning_of_month(), today}
  end

  defp first_click_date(link_ids) do
    from(c in ClickEvent, where: c.link_id in ^link_ids, select: min(c.occurred_at))
    |> Repo.one()
    |> case do
      nil -> nil
      %DateTime{} = dt -> DateTime.to_date(dt)
    end
  end

  defp daily(link_ids, from, to) do
    counts = grouped_counts(link_ids, from, to, "date(?)")

    from
    |> Date.range(to)
    |> Enum.map(fn date -> {date, Map.get(counts, Date.to_iso8601(date), 0)} end)
  end

  defp monthly(link_ids, from, to) do
    counts = grouped_counts(link_ids, from, to, "strftime('%Y-%m', ?)")

    from
    |> months_until(Date.beginning_of_month(to))
    |> Enum.map(fn date -> {date, Map.get(counts, month_key(date), 0)} end)
  end

  defp months_until(from, last) do
    Stream.iterate(from, &Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, last) != :gt))
  end

  defp month_key(date), do: date |> Date.to_iso8601() |> String.slice(0, 7)

  defp grouped_counts(link_ids, from, to, "date(?)") do
    from(c in ClickEvent,
      where: c.link_id in ^link_ids,
      where: c.occurred_at >= ^day_start(from) and c.occurred_at < ^day_start(Date.add(to, 1)),
      group_by: fragment("date(?)", c.occurred_at),
      select: {fragment("date(?)", c.occurred_at), count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp grouped_counts(link_ids, from, to, _month_fragment) do
    from(c in ClickEvent,
      where: c.link_id in ^link_ids,
      where: c.occurred_at >= ^day_start(from) and c.occurred_at < ^day_start(Date.add(to, 1)),
      group_by: fragment("strftime('%Y-%m', ?)", c.occurred_at),
      select: {fragment("strftime('%Y-%m', ?)", c.occurred_at), count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp day_start(date), do: DateTime.new!(date, ~T[00:00:00])

  def top_referrers(link_id, limit \\ 10) do
    Repo.all(
      from(c in ClickEvent,
        where: c.link_id == ^link_id,
        group_by: c.referrer,
        select: {c.referrer, count(c.id)},
        order_by: [desc: count(c.id)],
        limit: ^limit
      )
    )
    |> Enum.map(fn
      {nil, count} -> {"(direct)", count}
      {referrer, count} -> {referrer, count}
    end)
  end

  @doc "Coarse browser families from stored user agents."
  def browsers(link_id) do
    Repo.all(
      from(c in ClickEvent,
        where: c.link_id == ^link_id,
        group_by: c.user_agent,
        select: {c.user_agent, count(c.id)}
      )
    )
    |> Enum.reduce(%{}, fn {user_agent, count}, acc ->
      Map.update(acc, browser_family(user_agent), count, &(&1 + count))
    end)
    |> Enum.sort_by(fn {_family, count} -> -count end)
  end

  defp browser_family(nil), do: "Unknown"

  defp browser_family(user_agent) do
    downcased = String.downcase(user_agent)

    cond do
      String.contains?(downcased, ["bot", "crawler", "spider", "curl/", "wget/"]) -> "Bot"
      String.contains?(user_agent, "Edg/") -> "Edge"
      String.contains?(downcased, ["opr/", "opera"]) -> "Opera"
      String.contains?(user_agent, "Firefox/") -> "Firefox"
      String.contains?(user_agent, "Chrome/") -> "Chrome"
      String.contains?(user_agent, "Safari/") -> "Safari"
      true -> "Other"
    end
  end
end
