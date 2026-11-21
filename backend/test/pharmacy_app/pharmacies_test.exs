defmodule PharmacyApp.PharmaciesTest do
  use ExUnit.Case, async: true

  alias PharmacyApp.Pharmacies

  @berlin {52.52, 13.405}
  @hamburg {53.5511, 9.9937}

  def google_place(lat, lng, name \\ "Apotheke Mitte") do
    %Googly.Places.Model.GoogleMapsPlacesV1Place{
      id: "place-1",
      display_name: %Googly.Places.Model.GoogleTypeLocalizedText{text: name},
      formatted_address: "Ritterstraße 12, 10969 Berlin",
      location: %Googly.Places.Model.GoogleTypeLatLng{latitude: lat, longitude: lng}
    }
  end

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

  describe "from_google/2" do
    test "maps Google wire fields to the app struct" do
      pharmacy = Pharmacies.from_google(google_place(52.5200, 13.4050), @berlin)

      assert pharmacy.id == "place-1"
      assert pharmacy.display_name == "Apotheke Mitte"
      assert pharmacy.address == "Ritterstraße 12, 10969 Berlin"
      assert pharmacy.lat == 52.5200
      assert pharmacy.lng == 13.4050
      assert pharmacy.distance_m >= 0
      assert pharmacy.open_now == nil
      assert pharmacy.opening_hours == nil
      # same point => ~0 distance
      assert pharmacy.distance_m < 10
    end

    test "maps currentOpeningHours to open_now and weekday descriptions" do
      place =
        google_place(52.5200, 13.4050)
        |> struct!(current_opening_hours: opening_hours())

      pharmacy = Pharmacies.from_google(place, @berlin)

      assert pharmacy.open_now == true
      assert pharmacy.opening_hours == ["Mon: 08:00–20:00", "Tue: 08:00–20:00"]
    end

    defp opening_hours do
      %Googly.Places.Model.GoogleMapsPlacesV1PlaceOpeningHours{
        open_now: true,
        weekday_descriptions: ["Mon: 08:00–20:00", "Tue: 08:00–20:00"]
      }
    end

    test "returns nil and skips distance computation when location is missing" do
      # Google omits `location` unless it is requested in the field mask.
      place = %Googly.Places.Model.GoogleMapsPlacesV1Place{id: "place-no-loc"}

      assert Pharmacies.from_google(place, @berlin) == nil
    end

    test "computes distance in metres" do
      pharmacy = Pharmacies.from_google(google_place(elem(@hamburg, 0), elem(@hamburg, 1)), @berlin)
      assert pharmacy.distance_m > 252_000
    end
  end

  describe "put_walk/2" do
    defp summary(legs) do
      %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummary{legs: legs}
    end

    test "attaches walking duration and distance from the first leg" do
      leg = %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummaryLeg{
        distance_meters: 540,
        duration: "726s"
      }

      pharmacy = pharmacy(300)
      walked = Pharmacies.put_walk(pharmacy, summary([leg]))

      assert walked.walk_duration_s == 726
      assert walked.walk_distance_m == 540
      assert walked.distance_m == 300
    end

    test "no-op on nil summary or empty legs" do
      pharmacy = pharmacy(300)
      assert Pharmacies.put_walk(pharmacy, nil) == pharmacy
      assert Pharmacies.put_walk(pharmacy, summary([])) == pharmacy
    end
  end

  describe "filter/2 and sort/1" do
    def pharmacy(m) do
      %Pharmacies{
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
      assert Enum.map(Pharmacies.sort([pharmacy(300), pharmacy(100), pharmacy(200)]), & &1.distance_m) ==
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
