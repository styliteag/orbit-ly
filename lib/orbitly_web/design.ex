defmodule OrbitlyWeb.Design do
  @moduledoc """
  The three switchable UI designs. Each is a daisyUI theme (app.css) plus,
  on the links page, its own layout module under `OrbitlyWeb.LinksLive.*`.

  The choice is stored in a long-lived cookie (`orbitly_design`) mirrored
  into the session so LiveViews can read it on mount; `orbit` is the default.
  """

  @designs ~w(orbit bench soft)
  @default "orbit"

  def all, do: @designs
  def default, do: @default

  def validate(design) when design in @designs, do: design
  def validate(_other), do: @default

  def name("orbit"), do: "Orbit"
  def name("bench"), do: "Bench"
  def name("soft"), do: "Soft"
end
