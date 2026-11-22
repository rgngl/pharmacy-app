defmodule PharmacyAppWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint PharmacyAppWeb.Endpoint

  test "renders the 404 template" do
    assert PharmacyAppWeb.ErrorJSON.render("404.json", %{}) == %{errors: ["not found"]}
  end

  test "renders the 500 template" do
    assert PharmacyAppWeb.ErrorJSON.render("500.json", %{}) == %{
             errors: ["internal server error"]
           }
  end

  test "unknown templates fall back to the internal-server-error payload" do
    assert PharmacyAppWeb.ErrorJSON.render("418.json", %{}) == %{
             errors: ["internal server error"]
           }
  end

  test "an unknown /api path renders the JSON 404 payload" do
    conn =
      build_conn()
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> get("/api/nope")

    assert conn.status == 404
    assert %{"errors" => ["not found"]} = Jason.decode!(conn.resp_body)
  end
end
