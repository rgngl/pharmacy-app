defmodule PharmacyAppWeb.PageHTML do
  @moduledoc """
  Embedded HEEx templates for the pharmacy search page.
  """

  use Phoenix.Component

  embed_templates "page_html/*"

  @doc """
  Human distance: under 1000 m → "850 m", otherwise kilometres with one
  decimal ("1.2 km").
  """
  def format_distance(m) when is_number(m) and m < 1000 do
    "#{round(m)} m"
  end

  def format_distance(m) when is_number(m) do
    km = m / 1000
    "#{:erlang.float_to_binary(km, decimals: 1)} km"
  end

  def format_distance(nil), do: ""

  @doc """
  True when `m` is the radius currently in effect: the parsed submitted
  `radius_m`, or the 1000 m default when absent/invalid.
  """
  def active_radius?(submitted, m) when is_map(submitted) and is_integer(m) do
    case Float.parse(to_string(submitted["radius_m"] || "")) do
      {r, ""} when is_number(r) and r >= 1 -> trunc(r) == m
      _ -> m == 1000
    end
  end

  @doc """
  Radius shown in the empty-state message: parsed submitted value or the
  default 1000 m when absent/invalid.
  """
  def radius_text(submitted) when is_map(submitted) do
    case Float.parse(to_string(submitted["radius_m"] || "")) do
      {r, ""} when is_number(r) and r >= 1 -> "#{trunc(r)} m"
      _ -> "1000 m"
    end
  end
end
