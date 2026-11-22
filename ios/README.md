# PharmacyApp (iOS)

SwiftUI client for the pharmacy JSON API (`GET /api/pharmacies`). Single
target, iOS 17+, no external dependencies — nothing to install beyond Xcode.

The fastest path is a **simulator run against the live backend** (no API key,
no local server). Steps for all three setups below.

## Quickstart

Requirements: Xcode 15+ on macOS (the project needs the iOS 17 SDK). An
Apple Developer account is **not** required for the simulator.

1. Open the project and run:

   ```sh
   open PharmacyApp.xcodeproj
   ```

   Select the shared **PharmacyApp** scheme, pick an iPhone simulator, and
   press **Cmd+R**.

2. In the app, either type an address, or tap **Use my location** — the
   first tap triggers the location permission prompt. On the Simulator,
   feed a fix via **Features ▸ Location ▸ Custom Location**.

Out of the box the Debug configuration points at `http://localhost:4000`,
so without a local backend you get connection errors. Pick one:

| Setup | What to do |
|---|---|
| Live backend (zero setup) | Change `PHARMACY_BASE_URL` to `https://pharmacy-app.fly.dev` in the target's Build Settings (Debug config), run again. |
| Local backend | Run the Phoenix server first (see next section). |
| Own device | See "On a physical device" below. |

## With a local backend

Debug builds call `http://localhost:4000`; start the Phoenix server in a
second terminal (the app needs no API key of its own — the server holds it):

```sh
cd ../backend
GOOGLE_MAPS_API_KEY=your-key-here mix phx.server   # listens on :4000
```

Then Cmd+R in Xcode. See [`../backend/README.md`](../backend/README.md) for
the full backend setup.

## On a physical device

`DEVELOPMENT_TEAM` is empty in the project. To run on hardware:

1. In Xcode ▸ Signing & Capabilities, select your personal team.
2. The device can't reach `localhost` — either set `PHARMACY_BASE_URL` to
   `https://pharmacy-app.fly.dev`, or to your Mac's LAN IP
   (e.g. `http://192.168.1.10:4000`) while the local backend runs.
   Plain HTTP is only allowed for local/LAN hosts (ATS, see below); anything
   else must be HTTPS.

## Server base URL

The base URL is a build setting, not code: `PHARMACY_BASE_URL` is injected
into the bundle's `PharmacyBaseURL` and read once at launch by
[`AppConfig.swift`](PharmacyApp/AppConfig.swift).

- Debug: `http://localhost:4000`
- Release: `https://pharmacy-app.fly.dev` (used by Archive builds)

Repointing a build means changing the build setting — no code change. A
missing or non-http(s) value fails fast at launch (`preconditionFailure`).

## Troubleshooting

- **Connection refused / empty results** — the backend isn't running on
  `:4000` (check the terminal running `mix phx.server`; it hard-fails at
  boot without `GOOGLE_MAPS_API_KEY`).
- **Crash at launch mentioning `PHARMACY_BASE_URL`** — the build setting
  was removed or isn't a valid http(s) URL.
- **"Use my location" does nothing** — deny-once leaves the prompt state
  sticky; re-enable in Settings ▸ Privacy ▸ Location, or reset in the
  Simulator via **Device ▸ Erase All Content and Settings**.
