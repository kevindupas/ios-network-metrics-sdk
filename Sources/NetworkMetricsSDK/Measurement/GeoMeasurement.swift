import Foundation
import CoreLocation

internal final class GeoMeasurement: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<GeoResult?, Never>?
    private var settled = false

    func measure() async -> GeoResult? {
        return await withCheckedContinuation { cont in
            // CLLocationManager must be created and used on main thread
            DispatchQueue.main.async {
                let mgr = CLLocationManager()
                self.manager = mgr
                self.continuation = cont
                self.settled = false
                mgr.delegate = self
                mgr.desiredAccuracy = kCLLocationAccuracyBest
                mgr.requestWhenInUseAuthorization()
                mgr.requestLocation()

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.settle(result: nil)
                }
            }
        }
    }

    private func settle(result: GeoResult?) {
        guard !settled else { return }
        settled = true
        manager?.stopUpdatingLocation()
        manager = nil
        continuation?.resume(returning: result)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        settle(result: GeoResult(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy,
            altitude: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
            speed: loc.speed >= 0 ? loc.speed : nil,
            bearing: loc.course >= 0 ? loc.course : nil,
            provider: "CoreLocation"
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        settle(result: nil)
    }
}
