ExUnit.start()

# Phoenix transport tests dispatch through the endpoint without opening a port,
# but the app (and its supervised children) must be running.
{:ok, _} = Application.ensure_all_started(:pharmacy_app)
