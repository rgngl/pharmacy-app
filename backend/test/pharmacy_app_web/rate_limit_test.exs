defmodule PharmacyAppWeb.RateLimitTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint PharmacyAppWeb.Endpoint
  @table :pharmacy_rate_limit

  setup do
    # Tests opt into a tight limit via set_limit!/2 (called in the test body,
    # not setup: a previous test's on_exit delete races with this setup).
    # The global test config stays generous so controller tests hitting the
    # endpoint never trip the limiter.
    #
    # The fail-open test deletes the table entirely; the sweeper owns it and
    # recreates it here, otherwise every later test would fail open too.
    :ok = PharmacyAppWeb.RateLimit.Sweeper.ensure_table()
    :ets.delete_all_objects(@table)

    on_exit(fn ->
      Application.delete_env(:pharmacy_app, :rate_limit)
      Application.delete_env(:pharmacy_app, :service_opts)
      Application.delete_env(:pharmacy_app, :test_client_fn)
      Application.delete_env(:pharmacy_app, :test_geocoder_fn)
    end)
    :ok
  end

  defp set_limit!(limit, window_ms \\ 60_000, global_limit \\ 100_000) do
    Application.put_env(:pharmacy_app, :rate_limit,
      limit: limit,
      window_ms: window_ms,
      global_limit: global_limit
    )
  end

  defp set_client(result) do
    Application.put_env(:pharmacy_app, :service_opts, client: PharmacyApp.TestClient)
    Application.put_env(:pharmacy_app, :test_client_fn, fn _lat, _lng, _r, _opts -> result end)
  end

  defp get_as_ip(ip) do
    build_conn()
    |> Plug.Conn.put_req_header("fly-client-ip", ip)
    |> get("/api/pharmacies", lat: "52.52", lng: "13.405", radius_m: "1000")
  end

  test "allows requests up to the limit, then 429 with Retry-After" do
    set_limit!(3)
    set_client({:ok, []})

    for _ <- 1..3, do: assert(get_as_ip("203.0.113.1").status == 200)

    conn = get_as_ip("203.0.113.1")
    assert conn.status == 429
    assert %{"errors" => ["rate limit exceeded"]} = Jason.decode!(conn.resp_body)

    [retry_after] = Plug.Conn.get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) in 1..60
  end

  test "windows are per client IP" do
    set_limit!(3)
    set_client({:ok, []})

    for _ <- 1..3, do: assert(get_as_ip("203.0.113.1").status == 200)
    assert get_as_ip("203.0.113.1").status == 429
    assert get_as_ip("203.0.113.2").status == 200
  end

  test "limit resets after the window passes" do
    set_limit!(1, 100)
    set_client({:ok, []})

    assert get_as_ip("203.0.113.7").status == 200
    assert get_as_ip("203.0.113.7").status == 429

    Process.sleep(150)
    assert get_as_ip("203.0.113.7").status == 200
  end

  test "global cap denies across distinct IPs" do
    set_limit!(100, 60_000, 3)
    set_client({:ok, []})

    assert get_as_ip("203.0.113.11").status == 200
    assert get_as_ip("203.0.113.12").status == 200
    assert get_as_ip("203.0.113.13").status == 200
    assert get_as_ip("203.0.113.14").status == 429
    assert get_as_ip("203.0.113.14").status == 429
  end

  test "global cap resets after the window passes" do
    set_limit!(100, 100, 1)
    set_client({:ok, []})

    assert get_as_ip("203.0.113.11").status == 200
    assert get_as_ip("203.0.113.12").status == 429

    Process.sleep(150)
    assert get_as_ip("203.0.113.13").status == 200
  end

  test "health-check path is exempt" do
    for _ <- 1..10, do: assert(build_conn() |> get("/") |> Map.get(:status) == 200)
  end

  test "HTML searches with parameters are throttled" do
    set_limit!(2)
    set_client({:ok, []})
    Application.put_env(:pharmacy_app, :test_geocoder_fn, fn _address, _opts ->
      {:ok, %{lat: 52.52, lng: 13.405, formatted_address: "Alexanderplatz, Berlin"}}
    end)
    Application.put_env(:pharmacy_app, :service_opts,
      Keyword.put(Application.get_env(:pharmacy_app, :service_opts, []), :geocoder,
        PharmacyApp.TestClient
      )
    )

    for _ <- 1..2, do: assert(build_conn() |> get("/", q: "Berlin") |> Map.get(:status) == 200)
    assert build_conn() |> get("/", q: "Berlin") |> Map.get(:status) == 429
  end

  test "sweeper deletes expired windows and keeps the current one" do
    :ok = PharmacyAppWeb.RateLimit.Sweeper.ensure_table()

    # Stale window id sits well below the current one (monotonic time can be
    # negative on some platforms, making window ids negative too).
    current = div(System.monotonic_time(:millisecond), 60_000)
    :ets.insert(@table, {{"203.0.113.5", current - 5}, 3})
    :ets.insert(@table, {{"203.0.113.6", current}, 1})

    send(PharmacyAppWeb.RateLimit.Sweeper, :sweep)
    Process.sleep(50)

    assert :ets.lookup(@table, {"203.0.113.5", current - 5}) == []
    assert :ets.lookup(@table, {"203.0.113.6", current}) != []
  end

  test "fails open when the table is missing" do
    :ets.delete(@table)
    set_client({:ok, []})

    assert get_as_ip("203.0.113.9").status == 200
  end
end
