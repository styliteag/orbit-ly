defmodule Orbitly.VersionTest do
  use ExUnit.Case, async: true

  test "reports the version from the VERSION file" do
    expected = "VERSION" |> Path.expand(__DIR__ <> "/../..") |> File.read!() |> String.trim()

    assert Orbitly.version() == expected
  end
end
