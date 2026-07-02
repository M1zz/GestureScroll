import Foundation
import MultipeerConnectivity

/// Broadcasts the current GestureStatus to nearby companion devices (iPhone) over
/// MultipeerConnectivity — peer-to-peer, no shared Wi-Fi/router required. The
/// iPhone then relays to the Apple Watch via WatchConnectivity.
final class StatusBroadcaster: NSObject, ObservableObject {
    static let serviceType = "gscroll-st"   // ≤15 chars, lowercase/digits/hyphen

    private let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private var last: GestureStatus?
    // Serialize JSON encoding + peer send OFF the main thread. Since hand position
    // now changes every frame, this used to run per-frame on main and janked the
    // CGEvent scrolling / pinch timing. `last` is only touched on this queue.
    private let sendQueue = DispatchQueue(label: "status.broadcast")

    @Published private(set) var connectedCount = 0

    override init() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil,
                                               serviceType: StatusBroadcaster.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
    }

    /// Send the latest status (deduped). Uses unreliable delivery for low latency
    /// — dropping a stale frame is fine since the next one supersedes it.
    func send(_ status: GestureStatus) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            guard status != self.last else { return }
            self.last = status
            let peers = self.session.connectedPeers
            guard !peers.isEmpty, let data = try? JSONEncoder().encode(status) else { return }
            try? self.session.send(data, toPeers: peers, with: .unreliable)
        }
    }
}

extension StatusBroadcaster: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)   // auto-accept the companion app
    }
}

extension StatusBroadcaster: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.connectedCount = session.connectedPeers.count }
        if state == .connected {
            sendQueue.async { [weak self] in
                guard let self, let data = try? JSONEncoder().encode(self.last ?? .off) else { return }
                try? self.session.send(data, toPeers: [peerID], with: .reliable)   // send current on connect
            }
        }
    }
    func session(_: MCSession, didReceive _: Data, fromPeer _: MCPeerID) {}
    func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {}
    func session(_: MCSession, didStartReceivingResourceWithName _: String, fromPeer _: MCPeerID, with _: Progress) {}
    func session(_: MCSession, didFinishReceivingResourceWithName _: String, fromPeer _: MCPeerID, at _: URL?, withError _: Error?) {}
}
