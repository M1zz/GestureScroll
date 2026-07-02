import Foundation
import UIKit
import MultipeerConnectivity
import WatchConnectivity

/// Receives the Mac's GestureStatus over MultipeerConnectivity and relays it to
/// the Apple Watch over WatchConnectivity.
final class PhoneStatusReceiver: NSObject, ObservableObject {
    @Published var status: GestureStatus = .off
    @Published var connected = false

    // Local countdown for the nav cooldown ring. We stamp our OWN clock when a new
    // nav event arrives (status.navSeq changes), avoiding Mac↔iPhone clock skew.
    @Published var cooldownStart: Date?
    @Published var cooldownDuration: TimeInterval = 0
    private var lastNavSeq = 0

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    override init() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "gscroll-st")
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ status: GestureStatus) {
        DispatchQueue.main.async {
            // A new nav event (navSeq changed) starts the local cooldown ring.
            if status.navSeq != self.lastNavSeq {
                self.lastNavSeq = status.navSeq
                if status.navSeq > 0, status.navCooldown > 0 {
                    self.cooldownStart = Date()
                    self.cooldownDuration = status.navCooldown
                }
            }
            self.status = status
            self.relayToWatch(status)
        }
    }

    private func relayToWatch(_ status: GestureStatus) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(status) else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessageData(data, replyHandler: nil, errorHandler: nil) // low-latency live
        } else {
            try? s.updateApplicationContext(["status": data])             // latest-state fallback
        }
    }
}

extension PhoneStatusReceiver: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension PhoneStatusReceiver: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.connected = !session.connectedPeers.isEmpty }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let status = try? JSONDecoder().decode(GestureStatus.self, from: data) { apply(status) }
    }
    func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {}
    func session(_: MCSession, didStartReceivingResourceWithName _: String, fromPeer _: MCPeerID, with _: Progress) {}
    func session(_: MCSession, didFinishReceivingResourceWithName _: String, fromPeer _: MCPeerID, at _: URL?, withError _: Error?) {}
}

extension PhoneStatusReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
