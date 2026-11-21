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
  Walking time and distance along pedestrian paths: "7 min (540 m)".
  Shows whichever part is available; "" when the place has no routing
  summary. Uses `Map.get` so caches holding pre-walk structs don't crash.
  """
  def format_walk(pharmacy) do
    duration_s = Map.get(pharmacy, :walk_duration_s)
    distance_m = Map.get(pharmacy, :walk_distance_m)

    parts =
      [
        duration_part(duration_s),
        distance_part(distance_m)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    parts
  end

  defp duration_part(s) when is_number(s) and s < 60, do: "< 1 min"
  defp duration_part(s) when is_number(s), do: "#{round(s / 60)} min"
  defp duration_part(_), do: nil

  defp distance_part(m) when is_number(m), do: "(#{format_distance(m)})"
  defp distance_part(_), do: nil

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
