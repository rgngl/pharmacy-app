import Foundation

enum AppConfig {
    /// Phoenix server serving `GET /api/pharmacies`. The simulator can reach
    /// the host's localhost directly; on a physical device replace this with
    /// your Mac's LAN address (e.g. `http://192.168.1.10:4000`) or an
    /// HTTPS deployment URL.
    static let baseURL = URL(string: "http://localhost:4000")!
}
