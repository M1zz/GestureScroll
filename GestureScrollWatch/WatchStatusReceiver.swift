import Foundation
import WatchConnectivity

/// Receives the GestureStatus relayed from the paired iPhone over WatchConnectivity.
final class WatchStatusReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status: GestureStatus = .off

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ data: Data) {
        if let s = try? JSONDecoder().decode(GestureStatus.self, from: data) {
            DispatchQueue.main.async { self.status = s }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        apply(messageData)   // live updates while reachable
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["status"] as? Data { apply(data) }   // latest-state fallback
    }
}
