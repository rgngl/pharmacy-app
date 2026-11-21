import SwiftUI

private let radiusPresets = [500, 1000, 2000, 5000]

/// The search screen, mirroring the Phoenix web page top to bottom:
/// header, address box + "Use my location", radius chips, status/error
/// areas, result cards, Google attribution.
struct ContentView: View {
    @State private var model = SearchModel(
        api: PharmacyAPI(),
        location: {
            let provider = LocationProvider()
            let fix = try await provider.currentLocation()
            return (lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
        }
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchForm
                    chipsRow
                    statusArea
                }
                .padding()
            }
            .background(.background)
            .navigationTitle("Pharmacy Finder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Find a pharmacy")
                .font(.title2.bold())
            Text("Nearby locations, live opening hours & directions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                TextField("Enter an address", text: $model.queryText)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await model.search() }
                    }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button {
                    Task { await model.useMyLocation() }
                } label: {
                    Label("Use my location", systemImage: "location")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await model.search() }
                } label: {
                    Text("Search")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var chipsRow: some View {
        // Chips appear only once a search origin exists, like the web page.
        if model.origin != nil {
            HStack {
                Text("Radius:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(radiusPresets, id: \.self) { meters in
                    Button {
                        Task { await model.setRadius(meters) }
                    } label: {
                        Text(Format.radius(meters))
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                model.radiusM == meters ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(model.radiusM == meters ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if case .results(let pharmacies, _) = model.phase, !pharmacies.isEmpty {
                Text("Showing \(pharmacies.count) pharmacies within \(Format.radius(model.radiusM))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 48)
            }
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch model.phase {
        case .idle:
            emptyState("Enter an address above, or use your location, to find nearby pharmacies.")

        case .locating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Detecting your location…")
                    .foregroundStyle(.secondary)
            }

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Searching…")
                    .foregroundStyle(.secondary)
            }

        case .results(let pharmacies, let origin):
            VStack(alignment: .leading, spacing: 12) {
                Text("Showing pharmacies near \(origin.description)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(pharmacies, id: \.id) { pharmacy in
                    PharmacyCardView(pharmacy: pharmacy)
                }
                attribution
            }

        case .empty(let origin):
            VStack(alignment: .leading, spacing: 12) {
                Text("Showing pharmacies near \(origin.description)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                emptyState("No pharmacies found within \(Format.radius(model.radiusM)).")
            }

        case .invalid(let issues):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

        case .locateError(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "location.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button("Retry") {
                    Task { await model.retryLocation() }
                }
                .buttonStyle(.bordered)
            }

        case .banner(let message):
            Label(message, systemImage: "exclamationmark.octagon")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 32)
    }

    private var attribution: some View {
        Text("Search results by Google Maps")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    ContentView()
}
