defmodule OrbitlyWeb.Charts do
  @moduledoc """
  Server-rendered SVG charts. Deliberately no JavaScript charting library:
  LiveView already re-renders on data change, the strict CSP forbids new inline
  scripts, and the asset pipeline is esbuild + a vendor directory (no npm, no
  React — so React-only libraries such as TanStack Charts are out).

  Colour comes from `currentColor`, so a chart inherits whatever daisyUI theme
  colour its container sets (`text-primary`, …) and works in light and dark
  without a second palette. Text is rendered as HTML around the plot, never
  inside the stretched SVG viewBox, so labels stay crisp at any width.
  """

  use OrbitlyWeb, :html

  # Plot area in user units; the SVG is stretched to its container width.
  @width 1000
  @height 240

  @doc """
  Area chart over `{Date, count}` points. Hovering a column shows its exact
  value as a native tooltip (`<title>`), which needs no JS and no CSP nonce.
  """
  attr :id, :string, required: true
  attr :points, :list, required: true
  attr :granularity, :atom, default: :day
  attr :class, :string, default: "text-primary"

  attr :partial_last, :boolean,
    default: false,
    doc: "the last bucket is still running (today / this month) — drawn dashed"

  def area_chart(assigns) do
    assigns = assign(assigns, :plot, plot(assigns.points, assigns.partial_last))

    ~H"""
    <div id={@id} class={["w-full", @class]}>
      <div class="flex gap-3">
        <div class="flex flex-col justify-between h-56 text-xs opacity-50 tabular-nums shrink-0">
          <span>{@plot.max}</span>
          <span>{div(@plot.max, 2)}</span>
          <span>0</span>
        </div>

        <div class="flex-1 min-w-0">
          <svg
            viewBox={"0 0 #{@plot.width} #{@plot.height}"}
            class="w-full h-56 overflow-visible"
            preserveAspectRatio="none"
            role="img"
            aria-label={"#{@plot.total} clicks between #{first_label(@points, @granularity)} and #{last_label(@points, @granularity)}"}
          >
            <defs>
              <linearGradient id={"#{@id}-fill"} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="currentColor" stop-opacity="0.35" />
                <stop offset="100%" stop-color="currentColor" stop-opacity="0.02" />
              </linearGradient>
            </defs>

            <line
              :for={y <- @plot.grid}
              x1="0"
              x2={@plot.width}
              y1={y}
              y2={y}
              stroke="currentColor"
              stroke-opacity="0.12"
              stroke-dasharray="4 6"
              vector-effect="non-scaling-stroke"
            />

            <path d={@plot.area} fill={"url(##{@id}-fill)"} />
            <path
              d={@plot.line}
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linejoin="round"
              stroke-linecap="round"
              vector-effect="non-scaling-stroke"
            />
            <path
              :if={@plot.tail}
              d={@plot.tail}
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-dasharray="5 5"
              stroke-linecap="round"
              vector-effect="non-scaling-stroke"
            />

            <circle
              :if={@plot.peak}
              cx={elem(@plot.peak, 0)}
              cy={elem(@plot.peak, 1)}
              r="4"
              fill="currentColor"
              vector-effect="non-scaling-stroke"
            />

            <rect
              :for={{{date, count}, index} <- Enum.with_index(@points)}
              class="chart-hit"
              x={@plot.step * index}
              y="0"
              width={@plot.step}
              height={@plot.height}
            >
              <title>{hit_label(date, count, @granularity, @plot.partial_from == index)}</title>
            </rect>
          </svg>

          <div class="flex justify-between text-xs opacity-50 mt-2">
            <span :for={label <- axis_labels(@points, @granularity)}>{label}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "Ranked rows with a proportional bar — referrers, browsers, top links."
  attr :rows, :list, required: true, doc: "list of {label, count}"
  attr :empty_text, :string, default: "No clicks yet."
  attr :class, :string, default: "text-primary"

  def bar_list(assigns) do
    assigns = assign(assigns, :max, assigns.rows |> Enum.map(&elem(&1, 1)) |> max_or_zero())

    ~H"""
    <div class={["space-y-2", @class]}>
      <p :if={@rows == []} class="text-sm opacity-60">{@empty_text}</p>
      <div :for={{label, count} <- @rows} class="space-y-1">
        <div class="flex justify-between gap-4 text-sm">
          <span class="truncate text-base-content" title={label}>{label}</span>
          <span class="font-semibold tabular-nums shrink-0 text-base-content">{count}</span>
        </div>
        <div class="h-1.5 rounded-full bg-base-content/10 overflow-hidden">
          <div class="h-full rounded-full bg-current" style={"width: #{share(count, @max)}%"}></div>
        </div>
      </div>
    </div>
    """
  end

  ## -- geometry ------------------------------------------------------------

  defp plot(points, partial_last) do
    values = Enum.map(points, &elem(&1, 1))
    max = max_or_zero(values)
    count = length(values)
    step = if count > 0, do: @width / count, else: @width

    coords =
      Enum.with_index(values, fn value, index -> {x(index, count, step), y(value, max)} end)

    {solid, tail} = split_tail(coords, partial_last)

    %{
      width: @width,
      height: @height,
      max: max,
      total: Enum.sum(values),
      step: step,
      grid: [0.0, @height / 2, @height * 1.0],
      line: line_path(solid),
      tail: tail && line_path(tail),
      partial_from: if(partial_last and count > 0, do: count - 1),
      area: area_path(coords),
      peak: peak(coords, values, max)
    }
  end

  # A still-running bucket (today, this month) is not comparable to the
  # completed ones — its segment is drawn dashed instead of implying a drop.
  defp split_tail(coords, false), do: {coords, nil}
  defp split_tail(coords, _partial) when length(coords) < 2, do: {coords, nil}

  defp split_tail(coords, _partial) do
    {Enum.drop(coords, -1), Enum.take(coords, -2)}
  end

  defp hit_label(date, count, granularity, partial?) do
    "#{bucket_label(date, granularity)}: #{count} clicks" <>
      if partial?, do: " (so far)", else: ""
  end

  # Points sit in the middle of their bucket column, so a bar and the line
  # agree about where "that day" is.
  defp x(index, _count, step), do: step * index + step / 2
  defp y(_value, 0), do: @height * 1.0
  defp y(value, max), do: @height - value / max * (@height - 12)

  defp line_path([]), do: ""

  defp line_path([{x0, y0} | rest]) do
    Enum.reduce(rest, "M #{round1(x0)} #{round1(y0)}", fn {x, y}, acc ->
      acc <> " L #{round1(x)} #{round1(y)}"
    end)
  end

  defp area_path([]), do: ""

  defp area_path(coords) do
    {first_x, _} = List.first(coords)
    {last_x, _} = List.last(coords)

    line_path(coords) <>
      " L #{round1(last_x)} #{@height} L #{round1(first_x)} #{@height} Z"
  end

  defp peak(_coords, _values, 0), do: nil

  defp peak(coords, values, max) do
    index = Enum.find_index(values, &(&1 == max))
    Enum.at(coords, index)
  end

  defp round1(number), do: Float.round(number * 1.0, 1)

  defp max_or_zero([]), do: 0
  defp max_or_zero(values), do: Enum.max(values)

  defp share(_count, 0), do: 0
  defp share(count, max), do: round(count / max * 100)

  ## -- labels --------------------------------------------------------------

  @doc "Human label for one bucket."
  def bucket_label(date, :month), do: Calendar.strftime(date, "%b %Y")
  def bucket_label(date, _day), do: Calendar.strftime(date, "%d %b %Y")

  defp first_label([], _granularity), do: "—"
  defp first_label(points, granularity), do: points |> List.first() |> label(granularity)

  defp last_label([], _granularity), do: "—"
  defp last_label(points, granularity), do: points |> List.last() |> label(granularity)

  defp label({date, _count}, granularity), do: bucket_label(date, granularity)

  # Three to five evenly spaced ticks — more would collide on narrow screens.
  defp axis_labels([], _granularity), do: []

  defp axis_labels(points, granularity) do
    last = length(points) - 1
    ticks = min(4, last)

    if ticks < 1 do
      [label(List.first(points), granularity)]
    else
      for tick <- 0..ticks do
        points |> Enum.at(round(tick * last / ticks)) |> label(granularity)
      end
    end
  end
end
