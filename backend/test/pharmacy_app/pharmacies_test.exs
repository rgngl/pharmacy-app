defmodule PharmacyApp.PharmaciesTest do
  use ExUnit.Case, async: true

  alias PharmacyApp.Pharmacies
  alias PharmacyApp.Pharmacies.Pharmacy

  @berlin {52.52, 13.405}
  @hamburg {53.5511, 9.9937}

  describe "validate_params/1" do
    test "accepts valid bounds and clamps radius" do
      {:ok, params} = Pharmacies.validate_params(%{lat: 52.52, lng: 13.405, radius_m: 999_999})

      assert params == %{
               lat: 52.52,
               lng: 13.405,
               radius_m: 50_000,
               language_code: nil
             }

      {:ok, params} = Pharmacies.validate_params(%{lat: 52.52, lng: 13.405, radius_m: -5})
      assert params.radius_m == 1_000

      {:ok, params} = Pharmacies.validate_params(%{lat: 52.52, lng: 13.405})
      assert params.radius_m == 1_000
    end

    test "rejects lat out of bounds" do
      assert {:error, issues} = Pharmacies.validate_params(%{lat: 90.1, lng: 0})
      assert issues == ["lat must be a number between -90 and 90"]

      assert {:error, _} = Pharmacies.validate_params(%{lat: -90.1, lng: 0})
    end

    test "rejects lng out of bounds" do
      assert {:error, issues} = Pharmacies.validate_params(%{lat: 0, lng: 180.1})
      assert issues == ["lng must be a number between -180 and 180"]
    end

    test "accepts exact boundaries" do
      assert {:ok, _} = Pharmacies.validate_params(%{lat: 90, lng: 180})
      assert {:ok, _} = Pharmacies.validate_params(%{lat: -90, lng: -180})
    end

    test "reports both issues at once" do
      assert {:error, issues} = Pharmacies.validate_params(%{lat: "x", lng: "y"})
      assert length(issues) == 2
    end
  end

  describe "validate_options/1" do
    test "validates radius/language without coordinates" do
      assert Pharmacies.validate_options(%{radius_m: 300, language_code: "de"}) ==
               {:ok, %{radius_m: 300, language_code: "de"}}

      assert {:ok, opts} = Pharmacies.validate_options(%{})
      assert opts == %{radius_m: 1_000, language_code: nil}
    end

    test "rejects a bad language tag" do
      assert {:error, issues} = Pharmacies.validate_options(%{language_code: "not a tag!"})
      assert issues == ["language_code must be a BCP-47 language tag"]
    end
  end

  describe "effective_radius/1" do
    test "clamps to 1..50_000 and defaults on malformed input" do
      assert Pharmacies.effective_radius(999_999) == 50_000
      assert Pharmacies.effective_radius(540) == 540
      assert Pharmacies.effective_radius(0) == 1_000
      assert Pharmacies.effective_radius(-5) == 1_000
      assert Pharmacies.effective_radius(nil) == 1_000
      assert Pharmacies.effective_radius("500") == 1_000
    end
  end

  describe "haversine_m/4" do
    test "Berlin to Hamburg within 1%" do
      {lat1, lng1} = @berlin
      {lat2, lng2} = @hamburg
      d = Pharmacies.haversine_m(lat1, lng1, lat2, lng2)
      # Great-circle distance ≈ 255 km
      assert d > 252_000 and d < 258_000
    end

    test "zero distance" do
      {lat, lng} = @berlin
      assert Pharmacies.haversine_m(lat, lng, lat, lng) == 0.0
    end
  end

  describe "filter/2 and sort/1" do
    def pharmacy(m) do
      %Pharmacy{
        id: "p",
        display_name: "P",
        address: nil,
        lat: 0.0,
        lng: 0.0,
        distance_m: m,
        open_now: nil
      }
    end

    test "filter cuts beyond radius" do
      kept = Pharmacies.filter([pharmacy(100), pharmacy(1500), pharmacy(2000)], 1500)
      assert Enum.map(kept, & &1.distance_m) == [100, 1500]
    end

    test "sort orders ascending" do
      assert Enum.map(
               Pharmacies.sort([pharmacy(300), pharmacy(100), pharmacy(200)]),
               & &1.distance_m
             ) ==
               [100, 200, 300]
    end

    test "sort puts open pharmacies first, then by distance" do
      open = %{pharmacy(1000) | open_now: true}
      closed = %{pharmacy(100) | open_now: false}
      unknown = %{pharmacy(200) | open_now: nil}

      assert Pharmacies.sort([closed, open, unknown]) == [open, closed, unknown]
    end
  end
end
