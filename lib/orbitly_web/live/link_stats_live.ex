defmodule OrbitlyWeb.LinkStatsLive do
  @moduledoc """
  Click statistics for one link: a click curve over a selectable range
  (`ClickStats.per_bucket/2`, daily or monthly), headline numbers for that
  range, top referrers and browser families. Access is authorized through
  `Orbitly.Shortener` (owner/admin) before any stats query runs.

  Charts are server-rendered SVG (`OrbitlyWeb.Charts`) — no charting library,
  no client state, see that module for the why.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_user_required}

  alias Orbitly.Shortener
  alias Orbitly.Shortener.ClickStats
  alias OrbitlyWeb.Charts

  @range_labels %{
    "30d" => "30 days",
    "90d" => "90 days",
    "12m" => "12 months",
    "all" => "All time"
  }

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    case Shortener.get_link(id, socket.assigns.current_user) do
      {:ok, link} ->
        {:ok,
         socket
         |> assign(:page_title, "Stats — #{link.domain.hostname}/#{link.slug}")
         |> assign(:back_to, back_to(params["back"]))
         |> assign(:link, link)
         |> assign(:total, ClickStats.total(link.id))
         |> assign(:range, ClickStats.default_range())
         # module attributes are not assigns — the template needs it as one
         |> assign(:range_labels, @range_labels)
         |> assign(:referrers, ClickStats.top_referrers(link.id))
         |> assign(:browsers, ClickStats.browsers(link.id))
         |> load_series()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Link not found")
         |> push_navigate(to: ~p"/links")}
    end
  end

  @impl true
  def handle_event("range", %{"range" => range}, socket) do
    if range in ClickStats.ranges() do
      {:noreply, socket |> assign(:range, range) |> load_series()}
    else
      {:noreply, socket}
    end
  end

  defp load_series(socket) do
    series = ClickStats.per_bucket(socket.assigns.link.id, socket.assigns.range)
    counts = Enum.map(series.points, &elem(&1, 1))

    socket
    |> assign(:series, series)
    |> assign(:range_total, Enum.sum(counts))
    |> assign(:best, best_bucket(series))
  end

  defp best_bucket(%{points: []}), do: nil

  defp best_bucket(%{points: points, granularity: granularity}) do
    {date, count} = Enum.max_by(points, &elem(&1, 1))
    if count > 0, do: {Charts.bucket_label(date, granularity), count}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <.header>
          {@link.domain.hostname}/{@link.slug}
          <:subtitle>{@link.target_url}</:subtitle>
          <:actions>
            <.link navigate={@back_to} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
            </.link>
          </:actions>
        </.header>

        <div class="stats stats-vertical sm:stats-horizontal shadow border border-base-200 w-full">
          <div class="stat">
            <div class="stat-title">Total clicks</div>
            <div class="stat-value text-primary">{@total}</div>
            <div class="stat-desc">raw events, last 12 months (ADR-0005)</div>
          </div>
          <div class="stat">
            <div class="stat-title">In this range</div>
            <div class="stat-value">{@range_total}</div>
            <div class="stat-desc">{@range_labels[@range]}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Busiest {bucket_word(@series.granularity)}</div>
            <div class="stat-value text-secondary">{if @best, do: elem(@best, 1), else: 0}</div>
            <div class="stat-desc">{if @best, do: elem(@best, 0), else: "no clicks yet"}</div>
          </div>
        </div>

        <section class="space-y-2">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-60">Clicks over time</h2>
            <div class="join">
              <button
                :for={range <- ClickStats.ranges()}
                type="button"
                class={["join-item btn btn-xs", @range == range && "btn-active"]}
                phx-click="range"
                phx-value-range={range}
              >
                {@range_labels[range]}
              </button>
            </div>
          </div>

          <div class="card bg-base-100 border border-base-200 shadow-sm">
            <div class="card-body p-4">
              <Charts.area_chart
                id="per-day-chart"
                points={@series.points}
                granularity={@series.granularity}
                partial_last
              />
              <p class="text-xs opacity-50 mt-1">
                Dashed: the current {bucket_word(@series.granularity)} is still running.
              </p>
            </div>
          </div>
        </section>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <section class="space-y-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-60">Top referrers</h2>
            <div class="card bg-base-100 border border-base-200 shadow-sm">
              <div class="card-body p-4">
                <Charts.bar_list rows={@referrers} empty_text="No clicks yet." />
              </div>
            </div>
          </section>

          <section class="space-y-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-60">Browsers</h2>
            <div class="card bg-base-100 border border-base-200 shadow-sm">
              <div class="card-body p-4">
                <Charts.bar_list rows={@browsers} empty_text="No clicks yet." class="text-secondary" />
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp bucket_word(:month), do: "month"
  defp bucket_word(_day), do: "day"

  # The list page hands over its state (scope, sorting, page …) as a query
  # string so Back returns to the same view. Only the query is taken, never a
  # path — that keeps it from becoming an open redirect.
  defp back_to(nil), do: ~p"/links"
  defp back_to(""), do: ~p"/links"
  defp back_to(query), do: ~p"/links?#{URI.decode_query(query)}"
end
