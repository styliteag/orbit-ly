defmodule Orbitly.Shortener do
  use Ash.Domain,
    otp_app: :orbitly

  resources do
    resource Orbitly.Shortener.Domain do
      define :create_domain, action: :create
      define :list_domains, action: :read
      define :update_domain, action: :update
      define :make_primary, action: :make_primary
      define :destroy_domain, action: :destroy
    end

    resource Orbitly.Shortener.Link do
      define :create_link, action: :create
      define :list_links, action: :read
      define :update_link, action: :update
      define :destroy_link, action: :destroy
    end

    resource Orbitly.Shortener.ClickEvent do
      define :list_click_events, action: :read
    end
  end

  @doc """
  Click totals as %{link_id => count} in one grouped query. AshSqlite does
  not support count aggregates, and the caller passes already-authorized
  link ids, so plain Ecto is fine here.
  """
  def click_counts(link_ids) when is_list(link_ids) do
    import Ecto.Query

    from(c in Orbitly.Shortener.ClickEvent,
      where: c.link_id in ^link_ids,
      group_by: c.link_id,
      select: {c.link_id, count(c.id)}
    )
    |> Orbitly.Repo.all()
    |> Map.new()
  end
end
