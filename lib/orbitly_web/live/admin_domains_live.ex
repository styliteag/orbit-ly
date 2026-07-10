defmodule OrbitlyWeb.AdminDomainsLive do
  @moduledoc """
  Instance-admin domain management (ADR-0003): add redirect hostnames, toggle
  active, delete. The primary domain follows MAIN_DOMAIN (env, synced on boot)
  and is shown read-only — it cannot be deactivated or deleted here.
  """

  use OrbitlyWeb, :live_view

  on_mount {OrbitlyWeb.UserAuth, :live_admin_required}

  alias Orbitly.Shortener
  alias Orbitly.Shortener.Domain

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Domains")
     |> load_domains()
     |> assign_new_form()}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    changeset = Shortener.change_domain(%Domain{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "form"))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case Shortener.create_domain(params, socket.assigns.current_user) do
      {:ok, domain} ->
        {:noreply,
         socket
         |> put_flash(:info, "Domain #{domain.hostname} added")
         |> load_domains()
         |> assign_new_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "form"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add domain")}
    end
  end

  def handle_event("toggle-active", %{"id" => id}, socket) do
    with %Domain{} = domain <- find(socket, id),
         {:ok, _} <-
           Shortener.update_domain(
             domain,
             %{active: !domain.active},
             socket.assigns.current_user
           ) do
      {:noreply, load_domains(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update domain")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %Domain{} = domain <- find(socket, id),
         :ok <- Shortener.delete_domain(domain, socket.assigns.current_user) do
      {:noreply, socket |> put_flash(:info, "Domain deleted") |> load_domains()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not delete domain")}
    end
  end

  defp find(socket, id), do: Enum.find(socket.assigns.domains, &(&1.id == id))

  defp load_domains(socket) do
    domains = Shortener.list_domains()
    assign(socket, :domains, Enum.sort_by(domains, & &1.hostname))
  end

  defp assign_new_form(socket) do
    changeset = Shortener.change_domain(%Domain{})
    assign(socket, :form, to_form(changeset, as: "form"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <.header>
          Domains
          <:subtitle>Redirect hosts served by this instance</:subtitle>
        </.header>

        <.form for={@form} id="domain-form" phx-change="validate" phx-submit="save">
          <div class="flex flex-col sm:flex-row gap-2 items-start">
            <div class="flex-1 w-full">
              <.input field={@form[:hostname]} placeholder="go.example.com" class="input w-full" />
            </div>
            <.button phx-disable-with="Saving…" class="btn btn-primary">
              <.icon name="hero-plus" class="w-4 h-4" /> Add domain
            </.button>
          </div>
        </.form>

        <div class="space-y-2">
          <div
            :for={domain <- @domains}
            id={"domain-#{domain.id}"}
            class="card bg-base-100 border border-base-200 shadow-sm"
          >
            <div class="card-body py-3 px-4 sm:flex-row sm:items-center gap-3">
              <div class="min-w-0 flex-1 flex items-center gap-2">
                <span class="font-semibold truncate">{domain.hostname}</span>
                <span
                  :if={domain.is_primary}
                  class="badge badge-primary badge-sm"
                  title="Follows MAIN_DOMAIN"
                >
                  primary
                </span>
                <span :if={!domain.active} class="badge badge-warning badge-sm">inactive</span>
              </div>

              <div :if={!domain.is_primary} class="flex items-center gap-2 shrink-0">
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="toggle-active"
                  phx-value-id={domain.id}
                >
                  {if domain.active, do: "Deactivate", else: "Activate"}
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs text-error"
                  title="Delete domain"
                  phx-click="delete"
                  phx-value-id={domain.id}
                  data-confirm="Delete this domain and all its links?"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
