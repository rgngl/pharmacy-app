import Foundation
import Observation

/// Search origin, mirroring `PharmacyAppWeb.Params` origin modes. Kept after
/// a search so the radius chips can re-submit with the same origin — the web
/// app's chip behavior (address searches keep `q`, coordinate searches keep
/// lat/lng).
enum SearchOrigin: Hashable {
    case address(String)
    case coords(lat: Double, lng: Double)

    var description: String {
        switch self {
        case .address(let q): return q
        case .coords(let lat, let lng): return "\(lat), \(lng)"
        }
    }
}

/// One search screen phase, mirroring the web page's render states:
/// form-only, locating, loading, results/empty, inline errors, error banner.
enum SearchPhase: Equatable {
    case idle
    case locating
    case loading
    case results([Pharmacy], origin: SearchOrigin)
    case empty(SearchOrigin)
    case invalid([String])
    case locateError(String)
    case banner(String)
}

@MainActor
@Observable
final class SearchModel {
    private(set) var phase: SearchPhase = .idle
    private(set) var origin: SearchOrigin?
    var queryText = ""
    var radiusM = 1000

    private let api: PharmacyAPI
    private let location: () async throws -> (lat: Double, lng: Double)

    init(
        api: PharmacyAPI = PharmacyAPI(),
        location: @escaping () async throws -> (lat: Double, lng: Double)
    ) {
        self.api = api
        self.location = location
    }

    // -- Actions --------------------------------------------------------------

    /// Search button: address search unless the field holds raw coordinates.
    func search() async {
        let text = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .invalid(["Enter an address above, or use your location, to find nearby pharmacies."])
            return
        }
        await run(.address(text))
    }

    /// "Use my location": Geolocation flow — locating, then a coordinate
    /// search (drops any `q`, like the web form).
    func useMyLocation() async {
        phase = .locating
        do {
            let fix = try await location()
            queryText = ""
            await run(.coords(lat: fix.lat, lng: fix.lng))
        } catch {
            phase = .locateError(Self.locateMessage(error))
        }
    }

    /// Radius chip tap: re-run the current origin with the new radius.
    func setRadius(_ meters: Int) async {
        radiusM = meters
        guard let origin else { return }
        await run(origin)
    }

    func retryLocation() async {
        await useMyLocation()
    }

    /// Clear an error/banner back to the form.
    func dismiss() {
        phase = .idle
    }

    // -- Engine ---------------------------------------------------------------

    private func run(_ origin: SearchOrigin) async {
        self.origin = origin
        phase = .loading
        do {
            let pharmacies: [Pharmacy]
            switch origin {
            case .address(let q):
                pharmacies = try await api.search(lat: nil, lng: nil, q: q, radiusM: radiusM)
            case .coords(let lat, let lng):
                pharmacies = try await api.search(lat: lat, lng: lng, q: nil, radiusM: radiusM)
            }
            phase = pharmacies.isEmpty ? .empty(origin) : .results(pharmacies, origin: origin)
        } catch let error as APIError {
            phase = .banner(Self.apiMessage(error, origin: origin))
        } catch {
            phase = .banner(error.localizedDescription)
        }
    }

    // -- Error mapping ----------------------------------------------------------

    /// Maps APIError to banner text, mirroring the HTML controller's error
    /// states: not-found, upstream banner, transport banner.
    private static func apiMessage(_ error: APIError, origin: SearchOrigin) -> String {
        switch error {
        case .addressNotFound:
            if case .address(let q) = origin {
                return "Couldn't find an address matching “\(q)”."
            }
            return "Address not found."
        case .invalidParams(let issues):
            return issues.joined(separator: "\n")
        case .upstream(_, let message):
            return message
        case .upstreamUnavailable:
            return "The pharmacy service is temporarily unavailable. Please try again."
        case .transport(let message):
            return "Could not reach the server: \(message)"
        case .http(let status):
            return "Unexpected server response (HTTP \(status))."
        case .decoding:
            return "Unexpected response from the server."
        }
    }

    private static func locateMessage(_ error: Error) -> String {
        switch error as? LocationProvider.LocationError {
        case .denied:
            return "Location access was denied. Enable it in Settings, or search by address instead."
        case .timedOut:
            return "Couldn't determine your location in time."
        case .unavailable:
            return "Location services are unavailable."
        default:
            return "Couldn't determine your location."
        }
    }
}
