import Foundation

/// Number/unit formatting mirrored from
/// `PharmacyAppWeb.Components.format_distance/1` and friends.
enum Format {
    /// "850 m" / "1.2 km"; empty when distance is unknown.
    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "" }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    /// "< 1 min" / "11 min"; nil when there is no routing summary.
    static func walkDuration(_ seconds: Double?) -> String? {
        guard let seconds else { return nil }
        if seconds < 60 {
            return "< 1 min"
        }
        return "\(Int((seconds / 60).rounded())) min"
    }

    /// "500 m" / "1 km" / "2 km" / "5 km" for the chip row and empty states.
    static func radius(_ meters: Int) -> String {
        if meters < 1000 {
            return "\(meters) m"
        }
        let km = Double(meters) / 1000
        return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
    }

    enum Status {
        case open
        case closed
        case unknown
    }

    /// Status pill text/kind, mirroring `status_pill/1`.
    static func status(openNow: Bool?, closesAt: String?) -> (kind: Status, text: String) {
        switch openNow {
        case true:
            if let closesAt, !closesAt.isEmpty {
                return (.open, "Open until \(closesAt)")
            }
            return (.open, "Open now")
        case false:
            return (.closed, "Closed")
        case nil:
            return (.unknown, "Hours unavailable")
        }
    }

    /// Google Maps directions deep link — the same URL the web card uses.
    static func directionsURL(lat: Double?, lng: Double?) -> URL? {
        guard let lat, let lng else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(lat),\(lng)"),
        ]
        return components?.url
    }

    /// `tel:` URL with spaces stripped, mirroring the web Call button.
    static func callURL(_ phone: String?) -> URL? {
        guard let phone else { return nil }
        let normalized = phone.replacingOccurrences(of: " ", with: "")
        return URL(string: "tel:" + normalized)
    }
}
