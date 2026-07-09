defmodule Orbitly.Shortener.Slug do
  @moduledoc """
  Slug generation and validation rules.

  Generated slugs use an alphabet without visually ambiguous characters
  (no 0/O, 1/l/I). Custom slugs may use the full `[A-Za-z0-9_-]` set.
  """

  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
  @alphabet_size length(@alphabet)
  @format ~r/^[A-Za-z0-9_-]{1,64}$/
  @default_length 7

  def generate(length \\ @default_length) do
    length
    |> :crypto.strong_rand_bytes()
    |> :binary.bin_to_list()
    |> Enum.map(fn byte -> Enum.at(@alphabet, rem(byte, @alphabet_size)) end)
    |> List.to_string()
  end

  def valid_format?(slug) when is_binary(slug), do: Regex.match?(@format, slug)
  def valid_format?(_), do: false

  def reserved?(slug) when is_binary(slug) do
    String.downcase(slug) in Application.get_env(:orbitly, :reserved_slugs, [])
  end

  def reserved?(_), do: false

  # User-typed shortcuts for the two special links a (custom) domain can have.
  @root_inputs ~w(/ @)
  @catchall_inputs ~w(/* *)

  @doc """
  Maps a user-typed special slug to its stored form: `""` for the domain root
  (`/`, `@`) and `"*"` for the catch-all that answers any otherwise unmatched
  request (`/*`, `*`). Returns `nil` for a normal slug.
  """
  def special_slug(input) when is_binary(input) do
    case String.trim(input) do
      s when s in @root_inputs -> ""
      s when s in @catchall_inputs -> "*"
      _ -> nil
    end
  end

  def special_slug(_), do: nil

  @doc ~S(True for a stored special slug: the root `""` or the catch-all `"*"`.)
  def special?(slug), do: slug in ["", "*"]
end
