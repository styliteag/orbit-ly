defmodule OrbitlyWeb.LinksLive.Soft do
  @moduledoc """
  "Soft" design — warm white, friendly blue and coral, Bricolage Grotesque
  display, pill shapes everywhere. Signature: the list inverts the usual
  hierarchy — each link is a card with the SHORT link big (the thing you
  copy) and the original URL small beneath it.
  """

  use OrbitlyWeb, :html

  import OrbitlyWeb.LinksLive.Shared

  alias OrbitlyWeb.LinksLive.Bulk
  alias OrbitlyWeb.RelativeTime

  def page(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div id="links-page" data-design="soft" class="mx-auto max-w-3xl space-y-10 pb-10">
        <section class="text-center pt-8 space-y-5">
          <h1 class="brand-display text-6xl font-extrabold tracking-tight">
            Make it
            <span class="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              short.
            </span>
          </h1>
          <p class="opacity-60">Long links don't fit anywhere. Paste one — done.</p>

          <.form
            for={@form}
            id="link-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4 text-left"
          >
            <div class="relative">
              <.input
                field={@form[:target_url]}
                placeholder="Paste your long URL"
                class="input input-lg w-full !rounded-full bg-base-100 shadow-lg border-base-300/60 pl-6 pr-32 h-16"
              />
              <button
                type="submit"
                class="btn btn-primary rounded-full absolute right-2.5 top-2.5 px-6"
                phx-disable-with="Shortening…"
              >
                Shorten
              </button>
            </div>
            <.advanced_section form={@form} domains={@domains} show_advanced={@show_advanced} />
          </.form>
        </section>

        <section class="space-y-4">
          <.list_controls
            search={@search}
            total={@total}
            filtered_count={@filtered_count}
            page={@page}
            max_page={@max_page}
            page_size={@page_size}
            visible={@visible}
            selected={@selected}
          />

          <Bulk.bulk_bar
            selected={@selected}
            users={@users}
            current_user={@current_user}
            class="rounded-box border border-base-300/60 px-4 py-2"
          />

          <p
            :if={@visible == []}
            class="text-center opacity-60 py-10 bg-base-100 border border-base-300/60 rounded-box"
          >
            {empty_text(@search)}
          </p>

          <div
            :for={link <- @visible}
            id={"link-#{link.id}"}
            data-link-row
            class="group bg-base-100 rounded-box border border-base-300/60 shadow-sm hover:shadow-md transition-shadow px-6 py-4"
          >
            <div class="flex items-center gap-4">
              <Bulk.row_checkbox link={link} selected={@selected} />
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-1.5">
                  <a
                    href={short_url(link)}
                    target="_blank"
                    rel="noopener"
                    class="brand-display text-lg font-bold text-primary hover:underline truncate"
                  >
                    {link.domain.hostname}/{link.slug}
                  </a>
                  <.copy_button
                    text={short_url(link)}
                    class="btn-circle opacity-40 group-hover:opacity-100"
                  />
                  <.link_badges link={link} />
                </div>
                <p class="text-sm opacity-50 truncate" title={link.target_url}>
                  {link.target_url}
                </p>
                <div class="flex items-center gap-2 text-xs opacity-40 mt-0.5">
                  <span title={link.inserted_at}>{RelativeTime.ago(link.inserted_at)}</span>
                </div>
                <.owner_line link={link} current_user={@current_user} />
              </div>
              <div class="text-right shrink-0">
                <p class="brand-display text-2xl font-bold tabular-nums leading-none">
                  {Map.get(@click_counts, link.id, 0)}
                </p>
                <p class="text-xs opacity-40">views</p>
              </div>
              <.row_actions link={link} />
            </div>
            <div :if={@edit_id == link.id} class="mt-3 rounded-box bg-base-200/60 px-4">
              <.edit_panel edit_form={@edit_form} />
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
