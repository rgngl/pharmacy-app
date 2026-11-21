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

SwiftUI app in `ios/` (Xcode project, iOS 17+) that mirrors the web UI but
talks to the JSON API (`GET /api/pharmacies`) instead of rendering HTML:
address search (`q`), "Use my location" (CoreLocation → `lat`/`lng`),
radius chips that re-submit the current origin, pharmacy cards with
distance/open-now pills, and the same error mapping (422 issue list, 404
not-found, mirrored upstream errors).

```sh
# 1. run the backend (terminal A)
cd backend && GOOGLE_MAPS_API_KEY=your-key mix phx.server   # :4000

# 2. open the app (terminal B)
open ios/PharmacyApp.xcodeproj
```

- `ios/PharmacyApp/AppConfig.swift` holds the base URL: `http://localhost:4000`
  works in the iOS Simulator (ATS local networking is allowed in
  `Info.plist`); on a device point it at your Mac's LAN address or an
  HTTPS deployment.
- The app needs a location permission prompt the first time "Use my
  location" is used; the Simulator's Features ▸ Location menu can simulate
  a fix.
