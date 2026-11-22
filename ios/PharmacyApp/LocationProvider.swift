import CoreLocation
import Foundation

/// One-shot CoreLocation wrapper for the "Use my location" button, mirroring
/// the web page's Geolocation flow: locate → success or
/// denied/failed/timed-out error with a Retry affordance.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum LocationError: Error, Equatable {
        case denied
        case failed
        case timedOut
        case unavailable
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var requested = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation(timeout: TimeInterval = 10) async throws -> CLLocation {
        guard continuation == nil else { throw LocationError.failed }

        // Note: don't call CLLocationManager.locationServicesEnabled() here — it's a
        // synchronous IPC call that can block the main thread (see the console warning).
        // Services-disabled surfaces through didFailWithError below instead.

        requested = false
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(.failure(LocationError.timedOut))
            }
            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
            default:
                self.requestLocation()
            }
        }
    }

    private func requestLocation() {
        requested = true
        manager.requestLocation()
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.finish(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if (error as? CLError)?.code == .denied {
                self.finish(.failure(LocationError.denied))
            } else {
                self.finish(.failure(LocationError.failed))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Only react while a locate request is actually in flight.
            guard self.continuation != nil, !self.requested else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.requestLocation()
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
            default:
                break
            }
        }
    }
}
