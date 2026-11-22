# PharmacyApp

Finds the nearest pharmacies for a user's coordinates via the Google Places API.
Monorepo: Elixir/Phoenix backend + iOS app.

A running copy of the web app is available at https://pharmacy-app.fly.dev.

```
backend/   Elixir/Phoenix API (see backend/README.md)
ios/       iOS app (see ios/README.md)
```

## Backend

```sh
cd backend
mix deps.get
GOOGLE_MAPS_API_KEY=your-key-here mix phx.server   # http://localhost:4000
mix test
```

API: `GET /api/pharmacies?lat=…&lng=…&radius_m=…` — see [backend/README.md](backend/README.md) for full setup, parameters, and project layout.

## iOS

SwiftUI app in `ios/` (Xcode project, iOS 17+) that mirrors the web UI but
talks to the JSON API (`GET /api/pharmacies`) instead of rendering HTML.
Out of the box the Debug build targets `http://localhost:4000`, so run the
backend first, then open `ios/PharmacyApp.xcodeproj` and Cmd+R on a
simulator. See [ios/README.md](ios/README.md) for the quickstart, running
against the live API without a local backend, device setup, and
troubleshooting.
