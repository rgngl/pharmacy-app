defmodule PharmacyAppWeb.ParamsTest do
  use ExUnit.Case, async: true

  alias PharmacyAppWeb.Params

  # Minimal conn: Params only reads the accept-language header.
  defp conn, do: Plug.Test.conn(:get, "/")

  describe "parse/2" do
    test "non-map params are rejected wholesale" do
      parsed = Params.parse("lat=52.52", conn())

      assert parsed.origin == :none
      assert parsed.issues == ["invalid parameters"]
    end

    test "structured (non-scalar) lat is an input issue, not a crash" do
      parsed = Params.parse(%{"lat" => %{a: 1}, "lng" => "13.405"}, conn())

      assert parsed.origin == :coords
      assert parsed.issues == ["lat must be a number between -90 and 90"]
    end

    test "non-string q is rejected" do
      parsed = Params.parse(%{"q" => %{any: :thing}}, conn())

      assert parsed.issues == ["q must be a string"]
    end

    test "numeric lat/lng are accepted and normalized" do
      parsed = Params.parse(%{"lat" => 52.52, "lng" => 13}, conn())

      assert parsed.origin == :coords
      assert parsed.issues == []
      assert parsed.lat == 52.52
      assert parsed.lng == 13.0
    end

    test "unparseable coordinate string is an input issue" do
      parsed = Params.parse(%{"lat" => " 52,52 "}, conn())

      assert parsed.issues == ["lat must be a number between -90 and 90"]
    end

    test "radius fallbacks: unparseable binary, number, and structured value" do
      assert Params.parse(%{"radius_m" => "abc"}, conn()).radius_m == 1_000
      assert Params.parse(%{"radius_m" => 750}, conn()).radius_m == 750
      assert Params.parse(%{"radius_m" => %{"x" => 1}}, conn()).radius_m == 1_000
    end
  end
end
