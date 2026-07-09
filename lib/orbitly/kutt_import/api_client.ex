defmodule Orbitly.KuttImport.ApiClient do
  @moduledoc """
  Fetches links from a Kutt instance via its REST API
  (`GET /api/v2/links`, header `X-API-KEY`). Returns only the links owned by
  the API key's user — which is exactly what we want, since every imported
  link is reassigned to the orbit-ly admin anyway.
  """

  @behaviour Orbitly.KuttImport.Client

  # Kutt caps the page size at 50.
  @page 50

  @impl true
  def list_links(%{api_url: url, api_key: key}) do
    fetch_all(url, key, 0, [])
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp fetch_all(url, key, skip, acc) do
    response =
      Req.get!("#{url}/api/v2/links",
        headers: [{"x-api-key", key}],
        params: [limit: @page, skip: skip]
      )

    case response.status do
      200 ->
        page = response.body["data"] || []
        total = response.body["total"] || length(acc) + length(page)
        acc = acc ++ page

        if page != [] and length(acc) < total do
          fetch_all(url, key, skip + @page, acc)
        else
          {:ok, acc}
        end

      status ->
        {:error, "Kutt API returned HTTP #{status}"}
    end
  end
end
