import Foundation
import CoreLocation

internal class GeoMeasurement: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GeoResult?, Never>?

    func measure() async -> GeoResult? {
        return await withCheckedContinuation { cont in
            self.continuation = cont
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.continuation?.resume(returning: nil)
                self?.continuation = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let result = GeoResult(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy,
            altitude: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
            speed: loc.speed >= 0 ? loc.speed : nil,
            bearing: loc.course >= 0 ? loc.course : nil,
            provider: "CoreLocation"
        )
        continuation?.resume(returning: result)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
