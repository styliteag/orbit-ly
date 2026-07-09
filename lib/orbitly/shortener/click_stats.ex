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
