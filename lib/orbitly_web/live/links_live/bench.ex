defmodule OrbitlyWeb.LinksLive.Bench do
  @moduledoc """
  "Bench" design — ink-on-paper utility look, IBM Plex Mono for data,
  square corners (theme radius 0). No hero: a `shorten:` command bar sits
  directly above a dense, log-like table. Signature: slugs are mono chips
  that copy on click.
  """

  use OrbitlyWeb, :html

  import OrbitlyWeb.LinksLive.Shared

  alias OrbitlyWeb.LinksLive.{Bulk, Sort}
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
            visible={@visible}
            selected={@selected}
            scope={@scope}
            current_user={@current_user}
            class="px-3 py-2 border-b border-base-content/25 bg-base-200"
          />

          <Bulk.bulk_bar
            selected={@selected}
            users={@users}
            current_user={@current_user}
            class="px-3 py-2 border-b border-base-content/25"
          />

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr class="border-b-2 border-base-content/60">
                  <th class="w-8"></th>
                  <Sort.sort_header
                    field="short"
                    label="Short"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <Sort.sort_header
                    field="target"
                    label="Target"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <Sort.sort_header
                    :if={@current_user.admin}
                    field="owner"
                    label="Owner"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <Sort.sort_header
                    field="created"
                    label="Age"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                  />
                  <Sort.sort_header
                    field="clicks"
                    label="Hits"
                    sort_by={@sort_by}
                    sort_dir={@sort_dir}
                    class="text-right"
                  />
                  <th></th>
                </tr>
              </thead>
              <tbody class="brand-mono text-[13px]">
                <tr :if={@visible == []}>
                  <td
                    colspan={if @current_user.admin, do: "7", else: "6"}
                    class="text-center opacity-60 py-8 font-sans"
                  >
                    {empty_text(@search)}
                  </td>
                </tr>
                <%= for link <- @visible do %>
                  <tr
                    id={"link-#{link.id}"}
                    data-link-row
                    class="border-b border-base-content/10 hover:bg-base-200"
                  >
                    <td class="w-8">
                      <Bulk.row_checkbox link={link} selected={@selected} />
                    </td>
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
                      <.owner_line link={link} current_user={@current_user} show_owner={false} />
                    </td>
                    <td
                      :if={@current_user.admin}
                      class="max-w-[12rem] truncate opacity-70"
                      title={link.owner && link.owner.email}
                    >
                      {link.owner && link.owner.email}
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
                    <td
                      colspan={if @current_user.admin, do: "7", else: "6"}
                      class="bg-base-200/60 font-sans"
                    >
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
