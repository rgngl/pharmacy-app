defmodule PharmacyAppWeb.RateLimit do
  @default_limit 20
  @default_global_limit 300
  @default_window_ms :timer.seconds(60)

  @moduledoc """
  Per-client-IP and global fixed-window rate limiter for the API pipeline.

  Each request increments an atomic ETS counter keyed by client IP and
  window id, plus one shared counter under `:global` that caps the total
  request rate across all clients (a coordinated flood from many IPs still
  trips it). When either count for the current window exceeds its limit,
  the plug returns 429 with a `Retry-After` header. `:ets.update_counter`
  makes the increments atomic, so concurrent requests cannot slip past the
  limits; the tradeoff is a fixed (not sliding) window, which permits at
  most 2x the limit across a window boundary — acceptable for abuse
  protection on a single endpoint.

  The client IP comes from the `fly-client-ip` header set by the Fly proxy
  (never spoofable from outside Fly), falling back to `x-forwarded-for` and
  then `conn.remote_ip` for local development. Requests without any
  identifiable origin are allowed through rather than locking out the
  health check.

  Configuration under `:pharmacy_app, :rate_limit`:

    * `:limit` — requests per IP per window (default #{@default_limit})
    * `:global_limit` — requests per window across all IPs (default #{@default_global_limit})
    * `:window_ms` — window length (default #{inspect(@default_window_ms)})

  The GenServer only sweeps expired windows out of the table.
  """

  import Plug.Conn
  @table :pharmacy_rate_limit

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if limited_path?(conn) and ip_key(conn) do
      check(conn)
    else
      conn
    end
  end

  # The browser-scope health check is exempt so probes never consume quota.
  defp limited_path?(conn), do: conn.request_path != "/"

  defp check(conn) do
    ip = ip_key(conn)
    {limit, window_ms} = config()
    window = div(now_ms(), window_ms)

    # Plain atomic increments, unbounded; allow decisions are post-hoc
    # compares. A threshold+restart op ({2, 1, limit, 0}) would re-arm the
    # bucket on every deny, alternating deny/allow. The count grows at most
    # to the attack rate and the window rollover in the key resets it.
    count = :ets.update_counter(@table, {ip, window}, {2, 1}, {{ip, window}, 0})

    if count > limit do
      deny(conn, window_ms)
    else
      # Global ceiling over all IPs, same fixed-window mechanics; the
      # sweeper's key shape {any, window} covers :global with no changes.
      # Per-IP counts still consume quota even when the global cap denies —
      # coordinated floods must not get free retries by rotating IPs.
      global = :ets.update_counter(@table, {:global, window}, {2, 1}, {{:global, window}, 0})

      if global > global_limit() do
        deny(conn, window_ms)
      else
        conn
      end
    end
  rescue
    # Missing table (e.g. table not yet created during boot): fail open so
    # a limiter outage never takes the API down.
    ArgumentError -> conn
  end

  defp deny(conn, window_ms) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", retry_after_s(window_ms))
    |> send_resp(429, Jason.encode!(%{errors: ["rate limit exceeded"]}))
    |> halt()
  end

  defp config do
    opts = Application.get_env(:pharmacy_app, :rate_limit, [])
    {Keyword.get(opts, :limit, @default_limit), Keyword.get(opts, :window_ms, @default_window_ms)}
  end

  defp global_limit do
    opts = Application.get_env(:pharmacy_app, :rate_limit, [])
    Keyword.get(opts, :global_limit, @default_global_limit)
  end

  # Returns nil when no origin can be determined; `call/2` then allows the
  # request. Trust chain: Fly proxy header, generic proxy header, socket.
  defp ip_key(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] ->
        ip

      [] ->
        case get_req_header(conn, "x-forwarded-for") do
          [first | _] -> first |> String.split(",") |> hd() |> String.trim()
          [] -> :inet.ntoa(conn.remote_ip) |> to_string()
        end
    end
  rescue
    _ -> nil
  end

  defp retry_after_s(window_ms) do
    # rem/2 of a negative monotonic value stays negative (macOS starts
    # monotonic time far below zero); normalize into [0, window_ms) first.
    ms_into_window = rem(rem(now_ms(), window_ms) + window_ms, window_ms)
    max(div(window_ms - ms_into_window, 1000), 1) |> Integer.to_string()
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defmodule Sweeper do
    @moduledoc false

    use GenServer

    @default_limit 20
    @default_window_ms :timer.seconds(60)
    @sweep_interval Application.compile_env(
                      :pharmacy_app,
                      :rate_limit_sweep_interval,
                      :timer.seconds(10)
                    )
    @table :pharmacy_rate_limit

    @doc """
    Sweeps expired windows out of the rate-limit table. Owns the table:
    must be started before the Endpoint serves requests. `ensure_table/0`
    recreates the table after an external deletion (tests, or a gap while
    the sweeper itself is restarting).
    """
    def child_spec(_arg) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
    end

    def start_link do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    def ensure_table do
      GenServer.call(__MODULE__, :ensure_table)
    end

    @impl GenServer
    def init(_state) do
      create_table()
      Process.send_after(self(), :sweep, @sweep_interval)
      {:ok, []}
    end

    @impl GenServer
    def handle_call(:ensure_table, _from, state) do
      create_table()
      {:reply, :ok, state}
    end

    defp create_table do
      if :ets.whereis(@table) == :undefined do
        :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
      end

      :ok
    end

    @impl GenServer
    def handle_info(:sweep, state) do
      {_, window_ms} = config()
      stale_before = div(now_ms(), window_ms)

      # Entry is {{ip, window_id}, count}; binding the key tuple directly is
      # the only way to reach window_id (match specs cannot index tuples).
      :ets.select_delete(@table, [
        {{ {:"$1", :"$2"}, :_ }, [{:<, :"$2", stale_before}], [true]}
      ])

      Process.send_after(self(), :sweep, @sweep_interval)
      {:noreply, state}
    end

    defp config do
      opts = Application.get_env(:pharmacy_app, :rate_limit, [])
      {Keyword.get(opts, :limit, @default_limit), Keyword.get(opts, :window_ms, @default_window_ms)}
    end

    defp now_ms, do: System.monotonic_time(:millisecond)
  end
end
