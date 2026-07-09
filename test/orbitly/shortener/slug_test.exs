defmodule Orbitly.Shortener.SlugTest do
  use ExUnit.Case, async: true

  alias Orbitly.Shortener.Slug

  describe "generate/1" do
    test "generates slugs of the requested length in valid format" do
      for length <- [1, 7, 20] do
        slug = Slug.generate(length)
        assert String.length(slug) == length
        assert Slug.valid_format?(slug)
      end
    end

    test "defaults to 7 characters" do
      assert String.length(Slug.generate()) == 7
    end

    test "avoids visually ambiguous characters" do
      slugs = for _ <- 1..50, do: Slug.generate(20)
      refute Enum.any?(slugs, &String.match?(&1, ~r/[0O1lI]/))
    end
  end

  describe "valid_format?/1" do
    test "accepts letters, digits, dash and underscore up to 64 chars" do
      valid = ["a", "abc", "A-b_1", "UPPER", String.duplicate("x", 64)]
      invalid = ["", "a b", "ä", "a/b", "a.b", String.duplicate("x", 65), nil, 42]

      for slug <- valid, do: assert(Slug.valid_format?(slug), "expected valid: #{inspect(slug)}")

      for slug <- invalid,
          do: refute(Slug.valid_format?(slug), "expected invalid: #{inspect(slug)}")
    end
  end

  describe "reserved?/1" do
    test "matches the configured list case-insensitively" do
      assert Slug.reserved?("admin")
      assert Slug.reserved?("Admin")
      assert Slug.reserved?("LOGIN")
      refute Slug.reserved?("some-free-slug")
    end
  end
end
