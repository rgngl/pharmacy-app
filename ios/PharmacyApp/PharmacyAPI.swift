import Foundation

/// Typed errors mirroring `PharmaciesController.respond/2` status mapping.
enum APIError: Error, Equatable {
    /// 422 — invalid parameters, body lists issues.
    case invalidParams([String])
    /// 404 — `q` given but Google found no matching address.
    case addressNotFound
    /// Upstream error mirrored as-is (4xx) or mapped to 502.
    case upstream(status: Int, message: String)
    /// 502 with a plain-text body ("upstream unavailable").
    case upstreamUnavailable
    /// Any other non-200 status with an undecodable body.
    case http(Int)
    /// Network-level failure (offline, connection refused, timeout).
    case transport(String)
    case decoding(String)
}

/// Thin async client for `GET /api/pharmacies`.
///
/// Param semantics match `PharmacyAppWeb.Params`: explicit `lat`/`lng` win
/// over `q`; the caller sends either coordinates or an address, never both.
struct PharmacyAPI: Sendable {
    var baseURL: URL
    var session: URLSession

    init(baseURL: URL = AppConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func search(lat: Double?, lng: Double?, q: String?, radiusM: Int) async throws -> [Pharmacy] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.transport("invalid base URL")
        }
        components.path = "/api/pharmacies"

        var query: [URLQueryItem] = [URLQueryItem(name: "radius_m", value: String(radiusM))]
        if let lat, let lng {
            query.append(URLQueryItem(name: "lat", value: String(lat)))
            query.append(URLQueryItem(name: "lng", value: String(lng)))
        } else if let q, !q.isEmpty {
            query.append(URLQueryItem(name: "q", value: q))
        }
        components.queryItems = query

        guard let url = components.url else {
            throw APIError.transport("invalid request URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("not an HTTP response")
        }

        switch http.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode([Pharmacy].self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        case 422:
            throw APIError.invalidParams(decodeBody(data).messages)
        case 404:
            throw APIError.addressNotFound
        default:
            let body = decodeBody(data)
            for case .object(let status, let message) in body.items
            where (400..<500).contains(status) || status >= 500 {
                throw APIError.upstream(status: status, message: message)
            }
            if !body.messages.isEmpty {
                throw APIError.upstreamUnavailable
            }
            throw APIError.http(http.statusCode)
        }
    }

    private func decodeBody(_ data: Data) -> APIErrorBody {
        guard !data.isEmpty, let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) else {
            return APIErrorBody(items: [])
        }
        return body
    }
}

extension APIErrorBody {
    init(items: [Item]) {
        self.items = items
    }
}
