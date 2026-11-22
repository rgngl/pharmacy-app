defmodule PlacesFakeAdapter do
  @moduledoc """
  Req adapter module for PlacesAdapter request-path tests. The reply comes
  from the calling process' dictionary under `:places_fake_reply` (Req runs
  request steps, including the adapter, in the caller's process):

    * `{:ok, body}` — 200 with the wire-JSON map as the body
    * `{:http_error, status, body}` — non-2xx response
    * `{:raise, exception}` — adapter *returns* the exception (Req's
      transport-failure contract), surfacing as `{:error, exception}`
    * `{:raise!, exception}` — adapter raises, the exception escapes the
      request (exercises the instrumentation's rescue path)
    * `{:throw, token}` — adapter throws (exercises the catch path)

  The last seen `%Req.Request{}` is stored under `:places_fake_req` for
  assertions on headers, options, and the encoded body.
  """

  def run(req) do
    Process.put(:places_fake_req, req)

    case Process.get(:places_fake_reply) do
      {:ok, body} ->
        {req, %Req.Response{status: 200, body: body}}

      {:http_error, status, body} ->
        {req, %Req.Response{status: status, body: body}}

      {:raise, exception} ->
        {req, exception}

      {:raise!, exception} ->
        raise exception

      {:throw, token} ->
        throw(token)
    end
  end
end
