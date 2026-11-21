# PharmacyApp

Finds the nearest pharmacies for a user's coordinates via the Google Places API.
Monorepo: Elixir/Phoenix backend + iOS app.

```
backend/   Elixir/Phoenix API (see backend/README.md)
ios/       iOS app (Xcode project)
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

Open `ios/` in Xcode (project to be added).
