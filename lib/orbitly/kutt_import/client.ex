defmodule Orbitly.KuttImport.Client do
  @moduledoc """
  Behaviour for fetching links from a Kutt instance. The real implementation
  (`Orbitly.KuttImport.ApiClient`) talks to Kutt's HTTP API; tests inject a
  stub so the importer can be exercised without a network.
  """

  @doc """
  Returns all links visible to the configured API key. The config map is
  passed through verbatim from `Orbitly.KuttImport.run/1`.
  """
  @callback list_links(config :: map()) :: {:ok, [map()]} | {:error, term()}
end
