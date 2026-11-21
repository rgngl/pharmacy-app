import SwiftUI

/// One pharmacy result card, mirroring `pharmacy_card/1` from the web UI:
/// name + distance/walk pill, address, divider, hours row, actions.
struct PharmacyCardView: View {
    let pharmacy: Pharmacy

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pharmacy.displayName ?? "Unnamed pharmacy")
                    .font(.headline)
                Spacer()
                distancePill
            }

            if let address = pharmacy.address, !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .top) {
                statusPill
                Spacer()
                if let hours = pharmacy.openingHours, !hours.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(hours.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.footnote)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("View all hours")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                    }
                    .fixedSize()
                }
            }

            actions
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    // Distance pill: "<strong>1.2 km</strong> • ~11 min walk"
    private var distancePill: some View {
        HStack(spacing: 4) {
            Text(Format.distance(pharmacy.distanceM))
                .fontWeight(.semibold)
            if let walk = Format.walkDuration(pharmacy.walkDurationS) {
                Text("•")
                Text("~\(walk) walk")
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private var statusPill: some View {
        let pill = Format.status(openNow: pharmacy.openNow, closesAt: pharmacy.closesAt)
        return Text(pill.text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor(pill.kind), in: Capsule())
            .foregroundStyle(textColor(pill.kind))
    }

    private func backgroundColor(_ kind: Format.Status) -> Color {
        switch kind {
        case .open: return Color.green.opacity(0.15)
        case .closed: return Color.red.opacity(0.15)
        case .unknown: return Color.secondary.opacity(0.15)
        }
    }

    private func textColor(_ kind: Format.Status) -> Color {
        switch kind {
        case .open: return .green
        case .closed: return .red
        case .unknown: return .secondary
        }
    }

    private var actions: some View {
        HStack {
            if let url = Format.directionsURL(lat: pharmacy.lat, lng: pharmacy.lng) {
                Link(destination: url) {
                    Label("Get Directions", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            if let call = Format.callURL(pharmacy.phoneNumber) {
                Link(destination: call) {
                    Label("Call", systemImage: "phone")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.accentColor))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
