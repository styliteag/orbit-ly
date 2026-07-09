defmodule OrbitlyWeb.RelativeTime do
  @moduledoc """
  Coarse humanized time distances ("4 months ago") without a dependency.
  """

  @minute 60
  @hour 3600
  @day 86_400
  @month 2_592_000
  @year 31_536_000

  def ago(%DateTime{} = datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      seconds < @minute -> "just now"
      seconds < @hour -> plural(div(seconds, @minute), "minute")
      seconds < @day -> plural(div(seconds, @hour), "hour")
      seconds < @month -> plural(div(seconds, @day), "day")
      seconds < @year -> plural(div(seconds, @month), "month")
      true -> plural(div(seconds, @year), "year")
    end
  end

  def ago(nil), do: ""

  @doc "Future distance for expiry display (\"in 3 days\", \"expired\")."
  def until(%DateTime{} = datetime) do
    seconds = DateTime.diff(datetime, DateTime.utc_now())

    cond do
      seconds <= 0 -> "expired"
      seconds < @minute -> "in under a minute"
      seconds < @hour -> "in " <> bare_plural(div(seconds, @minute), "minute")
      seconds < @day -> "in " <> bare_plural(div(seconds, @hour), "hour")
      seconds < @month -> "in " <> bare_plural(div(seconds, @day), "day")
      seconds < @year -> "in " <> bare_plural(div(seconds, @month), "month")
      true -> "in " <> bare_plural(div(seconds, @year), "year")
    end
  end

  def until(nil), do: ""

  defp plural(n, unit), do: bare_plural(n, unit) <> " ago"
  defp bare_plural(1, unit), do: "1 #{unit}"
  defp bare_plural(n, unit), do: "#{n} #{unit}s"
end
