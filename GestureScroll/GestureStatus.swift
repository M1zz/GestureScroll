import Foundation

/// A snapshot of the Mac app's gesture state, shared with the companion iPhone
/// and Apple Watch apps. Codable so it can be sent over MultipeerConnectivity /
/// WatchConnectivity. SHARED across the macOS, iOS, and watchOS targets.
struct GestureStatus: Codable, Equatable {
    enum Kind: String, Codable { case off, noHand, idle, listening, command, pinch }
    enum Edge: String, Codable { case left, right, up, down }

    var kind: Kind
    var edge: Edge?            // hand nearing/leaving this side of the frame
    var lastGesture: String
    var mode: String

    // Navigation cooldown: after a Next/Previous fires, further nav is blocked for
    // `navCooldown` seconds. `navSeq` bumps once per fired nav event (it stays
    // constant *during* the cooldown, so it doesn't defeat the broadcaster's dedup).
    // The companion app starts a local countdown ring whenever `navSeq` changes.
    var navCooldown: TimeInterval = 0
    var navSeq: Int = 0

    // Live hand position + shape, so the companion can render the hand where it is
    // in the (mirrored, selfie-style) camera frame instead of only an arrow.
    // Coordinates are normalized 0...1 with (0,0) top-left, matching the Mac's
    // mirrored preview: handX grows to the user's right, handY grows downward.
    var handDetected: Bool = false
    var handX: Double = 0.5
    var handY: Double = 0.5
    var poseEmoji: String = ""   // ✊ ☝️ ✌️ 🤟 ✋ 🤏 — current hand shape

    // Keynote pinch-hold progress toward "Next" (0...1). The companion draws a
    // filling ring; reaching 1 means the slide advanced.
    var pinchProgress: Double = 0

    static let off = GestureStatus(kind: .off, edge: nil, lastGesture: "—", mode: "")
}
