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
end
