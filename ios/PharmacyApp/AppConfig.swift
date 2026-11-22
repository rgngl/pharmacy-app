import Foundation

/// Build-time server configuration. The base URL is baked into the bundle
/// by the `PHARMACY_BASE_URL` build setting (Info.plist `PharmacyBaseURL`):
///
/// - Debug builds:  `http://localhost:4000` (the local Phoenix server)
/// - Release builds: `https://pharmacy-app.fly.dev`
///
/// To repoint a build, change `PHARMACY_BASE_URL` in the target's build
/// configuration — no code change, no runtime override.
enum AppConfig {
    static let baseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "PharmacyBaseURL") as? String ?? ""
        guard let url = URL(string: raw), url.scheme == "http" || url.scheme == "https" else {
            preconditionFailure("PHARMACY_BASE_URL must be a valid http(s) URL, got '\(raw)'")
        }
        return url
    }()
}
