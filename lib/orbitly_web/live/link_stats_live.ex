defmodule OrbitlyWeb.LinkStatsLive do
  @moduledoc """
  Click statistics for one link: daily counts (30 days), top referrers,
  browser families. Access is authorized through `Orbitly.Shortener`
  (owner/admin) before any stats query runs.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_user_required}

  alias Orbitly.Shortener
  alias Orbitly.Shortener.ClickStats

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Shortener.get_link(id, socket.assigns.current_user) do
      {:ok, link} ->
        per_day = ClickStats.per_day(link.id)

        {:ok,
         socket
         |> assign(:page_title, "Stats — #{link.domain.hostname}/#{link.slug}")
         |> assign(:link, link)
         |> assign(:total, ClickStats.total(link.id))
         |> assign(:per_day, per_day)
         |> assign(:day_max, per_day |> Enum.map(&elem(&1, 1)) |> Enum.max())
         |> assign(:referrers, ClickStats.top_referrers(link.id))
         |> assign(:browsers, ClickStats.browsers(link.id))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Link not found")
         |> push_navigate(to: ~p"/links")}
    end
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
            <.link navigate={~p"/links"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
            </.link>
          </:actions>
        </.header>

        <div class="stats shadow border border-base-200">
          <div class="stat">
            <div class="stat-title">Total clicks</div>
            <div class="stat-value text-primary">{@total}</div>
            <div class="stat-desc">raw events, last 12 months (ADR-0005)</div>
          </div>
        </div>

        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide opacity-60">Last 30 days</h2>
          <div class="card bg-base-100 border border-base-200 shadow-sm">
            <div class="card-body p-4">
              <div class="flex items-end gap-[2px] h-32" id="per-day-chart">
                <div
                  :for={{date, count} <- @per_day}
                  class="flex-1 bg-primary/70 hover:bg-primary rounded-t min-h-[2px]"
                  style={"height: #{bar_height(count, @day_max)}%"}
                  title={"#{date}: #{count} clicks"}
                >
                </div>
              </div>
              <div class="flex justify-between text-xs opacity-50">
                <span>{@per_day |> List.first() |> elem(0)}</span>
                <span>{@per_day |> List.last() |> elem(0)}</span>
              </div>
            </div>
          </div>
        </section>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <section class="space-y-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-60">Top referrers</h2>
            <div class="card bg-base-100 border border-base-200 shadow-sm">
              <div class="card-body p-4 space-y-1">
                <p :if={@referrers == []} class="opacity-60 text-sm">No clicks yet.</p>
                <div
                  :for={{referrer, count} <- @referrers}
                  class="flex justify-between gap-4 text-sm"
                >
                  <span class="truncate">{referrer}</span>
                  <span class="font-semibold shrink-0">{count}</span>
                </div>
              </div>
            </div>
          </section>

          <section class="space-y-2">
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-60">Browsers</h2>
            <div class="card bg-base-100 border border-base-200 shadow-sm">
              <div class="card-body p-4 space-y-1">
                <p :if={@browsers == []} class="opacity-60 text-sm">No clicks yet.</p>
                <div :for={{family, count} <- @browsers} class="flex justify-between gap-4 text-sm">
                  <span>{family}</span>
                  <span class="font-semibold">{count}</span>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp bar_height(_count, 0), do: 0
  defp bar_height(count, max), do: round(count / max * 100)
end
