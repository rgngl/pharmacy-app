defmodule PharmacyAppWeb.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PharmacyApp.Pharmacies.Pharmacy
  alias PharmacyAppWeb.Components

  defp pharmacy(fields) do
    struct!(
      %Pharmacy{
        id: "p",
        display_name: "Apotheke",
        address: "Friedrichstraße 1",
        lat: 52.5215,
        lng: 13.405
      },
      fields
    )
  end

  # -- Pure formatters -------------------------------------------------------

  describe "format_distance/1" do
    test "metres under 1 km, kilometres above, empty without distance" do
      assert Components.format_distance(850) == "850 m"
      assert Components.format_distance(1520.0) == "1.5 km"
      assert Components.format_distance(nil) == ""
    end
  end

  describe "format_walk_duration/1" do
    test "sub-minute, minutes, and nil without routing summary" do
      assert Components.format_walk_duration(pharmacy(walk_duration_s: 30)) == "< 1 min"
      assert Components.format_walk_duration(pharmacy(walk_duration_s: 726)) == "12 min"
      assert Components.format_walk_duration(pharmacy(walk_duration_s: nil)) == nil
    end
  end

  # -- Icons -----------------------------------------------------------------

  describe "icon/1" do
    test "renders the phone icon" do
      html = render_component(&Components.icon/1, name: "phone")
      assert html =~ ~s(d="M22 16.92v3)
    end

    test "renders the chevron icon" do
      html = render_component(&Components.icon/1, name: "chevron")
      assert html =~ ~s(d="m6 9 6 6 6-6")
    end
  end

  # -- Pills and details -----------------------------------------------------

  describe "status_pill/1" do
    test "closes_at pill" do
      html = render_component(&Components.status_pill/1, open_now: true, closes_at: "16:00")
      assert html =~ "Open until 16:00"
    end

    test "open, closed, and unknown variants" do
      assert render_component(&Components.status_pill/1, open_now: true, closes_at: nil) =~
               "Open now"

      assert render_component(&Components.status_pill/1, open_now: false, closes_at: nil) =~
               "Closed"

      assert render_component(&Components.status_pill/1, open_now: nil, closes_at: nil) =~
               "Hours unavailable"
    end
  end

  describe "hours_details/1" do
    test "renders the collapsible hour list with the chevron" do
      html =
        render_component(&Components.hours_details/1, hours: ["Mon: 08:00–20:00", "Tue: 08:00–20:00"])

      assert html =~ "View all hours"
      assert html =~ ~s(d="m6 9 6 6 6-6")
      assert html =~ "<li>Mon: 08:00–20:00</li>"
      assert html =~ "<li>Tue: 08:00–20:00</li>"
    end

    test "renders nothing without hours" do
      assert render_component(&Components.hours_details/1, hours: []) == ""
      assert render_component(&Components.hours_details/1, hours: nil) == ""
    end
  end

  # -- Actions and pill composite -------------------------------------------

  describe "card_actions/1" do
    test "renders the Call button with a tel: link when a phone is present" do
      html =
        render_component(&Components.card_actions/1,
          lat: 52.5215,
          lng: 13.405,
          phone: "030 123456"
        )

      assert html =~ ~s(href="tel:030123456")
      assert html =~ ~s(d="M22 16.92v3)
    end

    test "omits the Call button without a phone" do
      html = render_component(&Components.card_actions/1, lat: 52.5215, lng: 13.405)
      refute html =~ "tel:"
    end
  end

  describe "distance_pill/1" do
    test "distance plus walk duration" do
      html =
        render_component(&Components.distance_pill/1,
          pharmacy: pharmacy(distance_m: 919, walk_duration_s: 726)
        )

      assert html =~ "919 m"
      assert html =~ "~12 min walk"
    end

    test "kilometres and no walk part without a routing summary" do
      html =
        render_component(&Components.distance_pill/1,
          pharmacy: pharmacy(distance_m: 1520.0, walk_duration_s: nil)
        )

      assert html =~ "1.5 km"
      refute html =~ "walk</span>"
    end
  end
end
