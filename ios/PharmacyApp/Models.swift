import Foundation

/// Mirrors the fields serialized by
/// `PharmacyAppWeb.PharmaciesController.serialize/1` (snake_case in JSON).
struct Pharmacy: Hashable, Sendable {
    let placeID: String?
    let displayName: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let distanceM: Double?
    let openNow: Bool?
    let openingHours: [String]?
    let closesAt: String?
    let phoneNumber: String?
    let walkDistanceM: Double?
    let walkDurationS: Double?

    /// Stable identity for list rendering; Google's place id is the real key,
    /// the rest is a display fallback for degenerate responses.
    var id: String {
        placeID ?? displayName ?? address ?? lat.map { "\($0),\(lng ?? 0)" } ?? UUID().uuidString
    }
}

extension Pharmacy: Decodable {
    private enum CodingKeys: String, CodingKey {
        case placeID = "id"
        case displayName = "display_name"
        case address
        case lat
        case lng
        case distanceM = "distance_m"
        case openNow = "open_now"
        case openingHours = "opening_hours"
        case closesAt = "closes_at"
        case phoneNumber = "phone_number"
        case walkDistanceM = "walk_distance_m"
        case walkDurationS = "walk_duration_s"
    }
}

/// Body of the error responses: `{"errors": [...]}` where each item is either
/// a plain string (422 issue list, 404, plain 502) or
/// `{"status": 4xx, "message": "..."}` (mirrored upstream errors).
struct APIErrorBody: Decodable, Sendable {
    enum Item: Sendable {
        case text(String)
        case object(status: Int, message: String)
    }

    let items: [Item]

    var messages: [String] {
        items.map {
            switch $0 {
            case .text(let text): return text
            case .object(_, let message): return message
            }
        }
    }

    enum CodingKeys: String, CodingKey { case errors }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var list = try container.nestedUnkeyedContainer(forKey: .errors)
        var decoded: [Item] = []
        while !list.isAtEnd {
            if let object = try? list.nestedContainer(keyedBy: ObjectKeys.self) {
                let status = try object.decodeIfPresent(Int.self, forKey: .status) ?? 0
                let message = try object.decodeIfPresent(String.self, forKey: .message) ?? ""
                decoded.append(.object(status: status, message: message))
            } else {
                decoded.append(.text(try list.decode(String.self)))
            }
        }
        items = decoded
    }

    private enum ObjectKeys: String, CodingKey { case status, message }
}
