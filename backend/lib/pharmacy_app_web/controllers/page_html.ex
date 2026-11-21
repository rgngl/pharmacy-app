defmodule PharmacyAppWeb.PageHTML do
  @moduledoc """
  Embedded HEEx templates for the pharmacy search page.
  """

  use Phoenix.Component
  import PharmacyAppWeb.Components

  embed_templates "page_html/*"

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
