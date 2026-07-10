defmodule OrbitlyWeb.LinksLive.Orbit do
  @moduledoc """
  "Orbit" design (default) — deep space navy, warm gold accent, Space
  Grotesk display. Signature: the orbital ellipse around the hero word.
  Links render as a row list with the short link first.
  """

  use OrbitlyWeb, :html

  import OrbitlyWeb.LinksLive.Shared

  alias OrbitlyWeb.RelativeTime

  def page(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div id="links-page" data-design="orbit" class="space-y-14 pb-10">
        <section class="text-center pt-8 space-y-6">
          <p class="text-xs tracking-[0.35em] uppercase text-secondary/80">Stylite Orbit-ly</p>
          <h1 class="brand-display text-5xl font-bold leading-tight">
            Cut your links
            <span class="relative inline-block px-3">
              <span class="text-primary">shorter</span>
              <svg
                viewBox="0 0 220 90"
                class="absolute -inset-x-4 -inset-y-3 w-[calc(100%+2rem)] h-[calc(100%+1.5rem)] pointer-events-none"
                fill="none"
                aria-hidden="true"
              >
                <ellipse
                  cx="110"
                  cy="45"
                  rx="102"
                  ry="32"
                  class="stroke-primary/50"
                  stroke-width="1.5"
                  transform="rotate(-7 110 45)"
                />
                <circle cx="22" cy="26" r="4" class="fill-primary" />
              </svg>
            </span>
          </h1>
          <p class="opacity-60 max-w-xl mx-auto">
            Paste a long URL and get a short one that stays in orbit.
          </p>

          <.form
            for={@form}
            id="link-form"
            phx-change="validate"
            phx-submit="save"
            class="max-w-2xl mx-auto space-y-4 text-left"
          >
            <div class="relative">
              <.input
                field={@form[:target_url]}
                placeholder="Paste your long URL"
                class="input input-lg w-full !rounded-full bg-base-200 border-base-content/15 pl-6 pr-16"
              />
              <button
                type="submit"
                class="btn btn-primary btn-circle absolute right-2 top-2"
                title="Shorten"
                aria-label="Shorten"
                phx-disable-with="…"
              >
                <.icon name="hero-arrow-up-right" class="w-5 h-5" />
              </button>
            </div>
            <.advanced_section form={@form} domains={@domains} show_advanced={@show_advanced} />
          </.form>
        </section>

        <section class="space-y-4">
          <h2 class="brand-display text-lg font-semibold">Recent links</h2>

          <div class="rounded-box bg-base-200/60 border border-base-content/10">
            <.list_controls
              search={@search}
              total={@total}
              filtered_count={@filtered_count}
              page={@page}
              max_page={@max_page}
              page_size={@page_size}
              class="p-4 border-b border-base-content/10"
            />

            <div class="divide-y divide-base-content/10">
              <p :if={@visible == []} class="p-10 text-center opacity-60">
                {empty_text(@search)}
              </p>
              <div
                :for={link <- @visible}
                id={"link-#{link.id}"}
                data-link-row
                class="px-5 py-3.5 hover:bg-base-content/[0.04] transition-colors"
              >
                <div class="flex items-center gap-4">
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-1.5">
                      <a
                        href={short_url(link)}
                        target="_blank"
                        rel="noopener"
                        class="brand-display font-semibold text-primary hover:underline truncate"
                      >
                        {link.domain.hostname}/{link.slug}
                      </a>
                      <.copy_button text={short_url(link)} />
                      <.link_badges link={link} />
                    </div>
                    <a
                      href={link.target_url}
                      target="_blank"
                      rel="noopener"
                      title={link.target_url}
                      class="text-sm opacity-60 hover:opacity-100 hover:underline block truncate"
                    >
                      {link.target_url}
                    </a>
                    <.owner_line link={link} current_user={@current_user} />
                  </div>
                  <span
                    class="text-xs opacity-40 whitespace-nowrap hidden sm:inline"
                    title={link.inserted_at}
                  >
                    {RelativeTime.ago(link.inserted_at)}
                  </span>
                  <span class="badge badge-outline border-primary/40 text-primary tabular-nums whitespace-nowrap">
                    {Map.get(@click_counts, link.id, 0)} views
                  </span>
                  <.row_actions link={link} />
                </div>
                <div :if={@edit_id == link.id} class="mt-3 rounded-box bg-base-300/50 px-4">
                  <.edit_panel edit_form={@edit_form} />
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
