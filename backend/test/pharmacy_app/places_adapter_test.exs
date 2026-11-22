defmodule PharmacyApp.Pharmacies.PlacesAdapterTest do
  use ExUnit.Case, async: true

  alias PharmacyApp.Pharmacies.Pharmacy
  alias PharmacyApp.Pharmacies.PlacesAdapter

  @origin {52.52, 13.405}

  def place(lat, lng, name) do
    %Googly.Places.Model.GoogleMapsPlacesV1Place{
      id: name,
      display_name: %Googly.Places.Model.GoogleTypeLocalizedText{text: name},
      formatted_address: "addr",
      location: %Googly.Places.Model.GoogleTypeLatLng{latitude: lat, longitude: lng}
    }
  end

  def no_location_place(name),
    do: %Googly.Places.Model.GoogleMapsPlacesV1Place{id: name}

  def summary(distance_meters, duration) do
    %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummary{
      legs: [
        %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummaryLeg{
          distance_meters: distance_meters,
          duration: duration
        }
      ]
    }
  end

  def empty_summary, do: %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummary{legs: []}

  describe "to_pharmacies/2" do
    test "pairs summaries by position" do
      result =
        PlacesAdapter.to_pharmacies(
          [place(52.5215, 13.405, "Near"), place(52.53, 13.405, "Far")],
          [summary(210, "180s"), summary(900, "600s")]
        )

      assert Enum.map(result, & &1.id) == ["Near", "Far"]
      assert Enum.find(result, &(&1.id == "Near")).walk_distance_m == 210
      assert Enum.find(result, &(&1.id == "Near")).walk_duration_s == 180
      assert Enum.find(result, &(&1.id == "Far")).walk_distance_m == 900
      assert Enum.find(result, &(&1.id == "Far")).walk_duration_s == 600
    end

    test "drops a place without coordinates together with its own summary" do
      # The valid place's summary is at position 1; dropping the
      # coordinate-less place at position 0 must not shift it.
      result =
        PlacesAdapter.to_pharmacies(
          [no_location_place("no-loc"), place(52.5215, 13.405, "Near")],
          [summary(999, "999s"), summary(210, "180s")]
        )

      assert Enum.map(result, & &1.id) == ["Near"]
      assert Enum.at(result, 0).walk_distance_m == 210
      assert Enum.at(result, 0).walk_duration_s == 180
    end

    test "an empty summary entry leaves walking fields nil" do
      result = PlacesAdapter.to_pharmacies([place(52.5215, 13.405, "Near")], [empty_summary()])

      assert Enum.map(result, & &1.id) == ["Near"]
      assert Enum.at(result, 0).walk_distance_m == nil
      assert Enum.at(result, 0).walk_duration_s == nil
    end

    test "a shorter summaries list leaves later places' walking fields nil" do
      result =
        PlacesAdapter.to_pharmacies(
          [place(52.5215, 13.405, "Near"), place(52.53, 13.405, "Far")],
          [summary(210, "180s")]
        )

      assert Enum.map(result, & &1.id) == ["Near", "Far"]
      assert Enum.find(result, &(&1.id == "Near")).walk_duration_s == 180
      assert Enum.find(result, &(&1.id == "Far")).walk_distance_m == nil
      assert Enum.find(result, &(&1.id == "Far")).walk_duration_s == nil
    end

    test "a missing summaries list leaves walking fields nil" do
      result = PlacesAdapter.to_pharmacies([place(52.5215, 13.405, "Near")], [])
      assert Enum.map(result, & &1.id) == ["Near"]
      assert Enum.at(result, 0).walk_distance_m == nil
      assert Enum.at(result, 0).walk_duration_s == nil
    end
  end

  describe "from_place/1" do
    test "maps Google wire fields without distance_m" do
      pharmacy = PlacesAdapter.from_place(place(52.5200, 13.4050, "Apotheke Mitte"))

      assert %Pharmacy{} = pharmacy
      assert pharmacy.id == "Apotheke Mitte"
      assert pharmacy.display_name == "Apotheke Mitte"
      assert pharmacy.address == "addr"
      assert pharmacy.lat == 52.5200
      assert pharmacy.lng == 13.4050
      assert pharmacy.distance_m == nil
      assert pharmacy.open_now == nil
      assert pharmacy.opening_hours == nil
      assert pharmacy.walk_distance_m == nil
      assert pharmacy.walk_duration_s == nil
    end

    test "returns nil when the location is missing" do
      assert PlacesAdapter.from_place(no_location_place("no-loc")) == nil
    end

    test "maps currentOpeningHours to open_now and weekday descriptions" do
      ph =
        place(52.5200, 13.4050, "A")
        |> struct!(current_opening_hours: opening_hours())
        |> PlacesAdapter.from_place()

      assert ph.open_now == true
      assert ph.opening_hours == ["Mon: 08:00–20:00", "Tue: 08:00–20:00"]
    end

    defp opening_hours do
      %Googly.Places.Model.GoogleMapsPlacesV1PlaceOpeningHours{
        open_now: true,
        weekday_descriptions: ["Mon: 08:00–20:00", "Tue: 08:00–20:00"]
      }
    end

    test "derives place-local closes_at while open" do
      # nextCloseTime decodes to UTC ("14:00Z" for a 16:00+02:00 close);
      # the offset restores place-local wall time.
      ph =
        place(52.5200, 13.4050, "A")
        |> struct!(
          utc_offset_minutes: 120,
          current_opening_hours: %{
            opening_hours()
            | next_close_time: DateTime.from_iso8601("2026-11-21T16:00:00+02:00") |> elem(1)
          }
        )
        |> PlacesAdapter.from_place()

      assert ph.closes_at == "16:00"
    end

    test "closes_at is nil for a closed place and for open-ended hours" do
      closed =
        place(52.5200, 13.4050, "A")
        |> struct!(
          current_opening_hours: %{
            opening_hours()
            | open_now: false,
              next_close_time: DateTime.from_iso8601("2026-11-22T09:00:00+02:00") |> elem(1)
          }
        )
        |> PlacesAdapter.from_place()

      assert closed.closes_at == nil

      # 24/7: open, but the close period is absent.
      always_open =
        place(52.5200, 13.4050, "A")
        |> struct!(current_opening_hours: opening_hours())
        |> PlacesAdapter.from_place()

      assert always_open.closes_at == nil
    end
  end

  describe "put_walk/2 and duration parsing" do
    def pharmacy(m \\ nil) do
      %Pharmacy{
        id: "p",
        display_name: "P",
        distance_m: m,
        lat: elem(@origin, 0),
        lng: elem(@origin, 1)
      }
    end

    test "attaches distance and duration parsed from '726s'" do
      walked = PlacesAdapter.put_walk(pharmacy(), summary(540, "726s"))

      assert walked.walk_distance_m == 540
      assert walked.walk_duration_s == 726
      assert walked.distance_m == nil
    end

    test "uses the first leg when several are present" do
      multi = %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummary{
        legs: [
          %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummaryLeg{
            distance_meters: 540,
            duration: "726s"
          },
          %Googly.Places.Model.GoogleMapsPlacesV1RoutingSummaryLeg{
            distance_meters: 100,
            duration: "100s"
          }
        ]
      }

      walked = PlacesAdapter.put_walk(pharmacy(), multi)

      assert walked.walk_distance_m == 540
      assert walked.walk_duration_s == 726
    end

    test "rounds fractional durations and nils unparseable ones" do
      assert PlacesAdapter.put_walk(pharmacy(), summary(10, "90.5s")).walk_duration_s == 91

      assert PlacesAdapter.put_walk(pharmacy(), summary(10, "not-a-duration")).walk_duration_s ==
               nil
    end

    test "no-op on nil summary or empty legs" do
      ph = pharmacy(300)
      assert PlacesAdapter.put_walk(ph, nil) == ph
      assert PlacesAdapter.put_walk(ph, empty_summary()) == ph
    end

    test "a non-binary duration leaves walk_duration_s nil" do
      assert PlacesAdapter.put_walk(pharmacy(), summary(10, nil)).walk_duration_s == nil
    end

    test "nil pharmacy passes through" do
      assert PlacesAdapter.put_walk(nil, summary(10, "60s")) == nil
    end
  end
end
