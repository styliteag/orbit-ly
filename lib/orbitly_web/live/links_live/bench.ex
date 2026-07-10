defmodule OrbitlyWeb.LinksLive.Bench do
  @moduledoc """
  "Bench" design — ink-on-paper utility look, IBM Plex Mono for data,
  square corners (theme radius 0). No hero: a `shorten:` command bar sits
  directly above a dense, log-like table. Signature: slugs are mono chips
  that copy on click.
  """

  use OrbitlyWeb, :html

  import OrbitlyWeb.LinksLive.Shared

  alias OrbitlyWeb.RelativeTime
  alias Phoenix.LiveView.JS

  def page(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} wide>
      <div id="links-page" data-design="bench" class="space-y-6 pb-10">
        <.form for={@form} id="link-form" phx-change="validate" phx-submit="save" class="space-y-3">
          <div class="border border-base-content/25 bg-base-100 flex items-stretch divide-x divide-base-content/25">
            <span class="brand-mono text-sm px-4 flex items-center opacity-50 select-none">
              shorten:
            </span>
            <div class="flex-1">
              <.input
                field={@form[:target_url]}
                placeholder="https://…"
                class="input w-full !border-0 brand-mono text-sm"
              />
            </div>
            <button type="submit" class="btn btn-primary px-6" phx-disable-with="…">
              Shorten ↵
            </button>
          </div>
          <.advanced_section form={@form} domains={@domains} show_advanced={@show_advanced} />
        </.form>

        <section class="border border-base-content/25">
          <.list_controls
            search={@search}
            total={@total}
            filtered_count={@filtered_count}
            page={@page}
            max_page={@max_page}
            page_size={@page_size}
            class="px-3 py-2 border-b border-base-content/25 bg-base-200"
          />

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr class="border-b-2 border-base-content/60">
                  <th class="text-[10px] uppercase tracking-[0.15em]">Short</th>
                  <th class="text-[10px] uppercase tracking-[0.15em]">Target</th>
                  <th class="text-[10px] uppercase tracking-[0.15em]">Age</th>
                  <th class="text-[10px] uppercase tracking-[0.15em] text-right">Hits</th>
                  <th></th>
                </tr>
              </thead>
              <tbody class="brand-mono text-[13px]">
                <tr :if={@visible == []}>
                  <td colspan="5" class="text-center opacity-60 py-8 font-sans">
                    {empty_text(@search)}
                  </td>
                </tr>
                <%= for link <- @visible do %>
                  <tr
                    id={"link-#{link.id}"}
                    data-link-row
                    class="border-b border-base-content/10 hover:bg-base-200"
                  >
                    <td class="whitespace-nowrap">
                      <button
                        type="button"
                        class="border border-base-content/25 bg-base-200 px-1.5 py-0.5 hover:border-primary hover:text-primary cursor-pointer"
                        title={"Copy #{short_url(link)}"}
                        aria-label="Copy short link"
                        phx-click={JS.dispatch("phx:copy", detail: %{text: short_url(link)})}
                      >
                        <span class="copy-idle">{link.domain.hostname}/{link.slug}</span>
                        <span class="copy-done hidden text-primary">copied ✓</span>
                      </button>
                      <.link_badges link={link} />
                    </td>
                    <td class="max-w-md">
                      <a
                        href={link.target_url}
                        target="_blank"
                        rel="noopener"
                        title={link.target_url}
                        class="block truncate hover:underline opacity-80"
                      >
                        {link.target_url}
                      </a>
                      <.owner_line link={link} current_user={@current_user} />
                    </td>
                    <td class="whitespace-nowrap opacity-50" title={link.inserted_at}>
                      {RelativeTime.ago(link.inserted_at)}
                    </td>
                    <td class="text-right tabular-nums font-semibold">
                      {Map.get(@click_counts, link.id, 0)}
                    </td>
                    <td>
                      <.row_actions link={link} />
                    </td>
                  </tr>
                  <tr :if={@edit_id == link.id} id={"edit-#{link.id}"}>
                    <td colspan="5" class="bg-base-200/60 font-sans">
                      <.edit_panel edit_form={@edit_form} />
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
