import Foundation
import CoreGraphics

/// Recognized high-level gestures.
enum Gesture: String {
    case scrollDown = "Scroll ↓"
    case scrollUp   = "Scroll ↑"
    case nextSlide  = "Next →"
    case prevSlide  = "Prev ←"
    case activate   = "Listening ✋"
}

/// Turns a stream of per-frame finger states into discrete gesture events.
/// The pose → action mapping is **mode-specific**:
///
///   Scroll (browser): 🤏 pinch-drag = grab the page (1:1, both ways) · ☝️ = up
///   Keynote:          ✌️ hold = Next · 🤟 hold = Previous (☝️/✊ do nothing,
///                     so natural presentation hand-talk can't change slides)
///   PDF:              ✊ = down · ☝️ = up · ✌️ = Next · 🤟 = Previous
///   Cursor (mouse):   hand steers the pointer · 🤏 pinch = click / pinch-move = drag
///
/// Safety layers: an open hand (✋) must "arm" Listening first; poses must be
/// held briefly (debounce, longer for Next/Previous); Next/Previous fire once
/// per hold and keep a `navCooldown` floor between fires.
final class GestureRecognizer {

    /// Called on the main thread when a discrete gesture fires.
    var onGesture: ((Gesture) -> Void)?

    /// Called on the main thread during a pinch-drag with the per-frame vertical
    /// movement (normalized; positive = downward). Lets the engine scroll smoothly
    /// in proportion to hand motion, instead of in fixed steps.
    var onScroll: ((CGFloat) -> Void)?

    /// Called every frame in Cursor mode (while armed) with the hand position
    /// (normalized, mirrored, top-left origin) and whether a pinch is held.
    /// The engine maps this to the screen and synthesizes mouse move/click/drag.
    var onCursor: ((CGPoint, Bool) -> Void)?

    // Tunables
    var cooldown: TimeInterval = 0.7        // min seconds between repeats while a pose is held
    var poseStableTime: TimeInterval = 0.25 // a pose must be held this long before it triggers
    var navPoseStableTime: TimeInterval = 0.6 // Next/Previous poses need a longer, deliberate hold
    var armWindow: TimeInterval = 6.0       // how long "armed" stays active after ✋ / last use
    var navCooldown: TimeInterval = 1.5     // hard minimum between Next/Previous signals
    var dragStep: CGFloat = 0.035           // hand travel (normalized) per pinch-drag scroll step
    var upScrollRate: CGFloat = 0.010       // smooth scroll-up speed per frame while one finger is held

    private(set) var armed = false
    private var armedUntil: Date = .distantPast
    private var lastFire: Date = .distantPast

    // Pose debounce / one-shot state
    private var pendingPose: Gesture?
    private var poseSince: Date = .distantPast
    private var firedThisHold = false
    private var lastNavFire: Date = .distantPast
    private var pinchAnchorY: CGFloat?             // previous-frame Y while pinching (Scroll)
    private var oneFingerSince: Date?             // when the one-finger scroll-up pose began

    /// 0...1 fill of the current Next/Previous pose-hold toward firing. The
    /// companion apps render this as a filling ring. Recomputed every frame.
    private(set) var pinchProgress: CGFloat = 0

    /// Scrolling repeats while the pose is held; page navigation fires once per hold.
    private func isRepeating(_ g: Gesture) -> Bool {
        g == .scrollUp || g == .scrollDown
    }

    /// Feed one frame of state. `indexTip`/`wrist` are unused by the pose-based
    /// recognizer but kept in the signature for the camera pipeline.
    func update(handDetected: Bool,
                indexTip: CGPoint?,
                wrist: CGPoint?,
                fingers: HandPoseCamera.FingerExtension,
                mode: GestureEngine.ControlMode) {

        let now = Date()

        // Expire armed mode.
        if armed && now > armedUntil { armed = false }

        guard handDetected else {
            pendingPose = nil
            firedThisHold = false
            pinchAnchorY = nil
            oneFingerSince = nil
            pinchProgress = 0
            return
        }

        // Count only the four non-thumb fingers — thumb detection is the least
        // reliable. (HandPoseCamera also majority-votes these over recent frames.)
        let count = [fingers.index, fingers.middle, fingers.ring, fingers.little]
            .filter { $0 }.count

        // --- Open hand (✋): arm Listening. Never changes a slide by itself. ---
        if count >= 4 {
            if !armed {
                armed = true
                fire(.activate, now: now, ignoreCooldown: true, ignoreArmed: true)
            }
            armedUntil = now.addingTimeInterval(armWindow)
            pendingPose = nil
            firedThisHold = false
            pinchProgress = 0
            // Cursor mode: an open palm still steers the pointer (never clicks).
            if mode == .cursor, armed, let p = wrist ?? indexTip {
                onCursor?(p, false)
            }
            return
        }
        pinchProgress = 0   // default; the nav pose-hold path sets it below

        guard armed else { return }

        // Keep armed while the hand is actively posing.
        armedUntil = now.addingTimeInterval(armWindow)

        // --- Cursor mode: every hand shape steers the pointer; 🤏 pinching
        //     (thumb tip to index tip) presses the mouse button and releasing
        //     the pinch lets go (집기 = 클릭, 집은 채 이동 = 드래그). A pinch
        //     barely moves the wrist the cursor tracks, so clicking doesn't
        //     shove the pointer the way clenching a fist did.
        //     All mapping/smoothing/debounce lives in the engine. ---
        if mode == .cursor {
            let pressing = fingers.pinch
            if let p = wrist ?? indexTip { onCursor?(p, pressing) }
            return
        }

        // --- Scroll mode (browser): both directions scroll smoothly ---
        //   • pinch-drag → the page follows the hand 1:1, BOTH directions
        //     (grab-and-drag, like touch scrolling — this is what makes it feel tight)
        //   • ☝️ one finger held → scroll up at a steady, smooth rate
        if mode == .scroll {
            if fingers.pinch, let y = wrist?.y ?? indexTip?.y {
                if let last = pinchAnchorY {
                    let dy = last - y             // +dy = hand moved up → scroll down
                    if dy != 0 { onScroll?(dy) }  // bidirectional: page tracks the hand
                }
                pinchAnchorY = y                  // track previous frame for continuity
                oneFingerSince = nil
                return
            }
            pinchAnchorY = nil
            if count == 1 {                       // one finger → smooth continuous scroll up
                if oneFingerSince == nil { oneFingerSince = now }
                if now.timeIntervalSince(oneFingerSince!) >= poseStableTime {
                    onScroll?(-upScrollRate)
                }
            } else {
                oneFingerSince = nil
            }
            return
        }

        // --- Map the pose to a semantic gesture, per mode (Keynote / PDF) ---
        let pose: Gesture?
        switch mode {
        case .scroll:   // handled above
            pose = nil
        case .cursor:   // handled above (continuous onCursor stream)
            pose = nil
        case .keynote:  // ONLY the two nav poses; ☝️ pointing and ✊ a resting
                        // fist — both common while presenting — do nothing.
            switch count {
            case 2:  pose = .nextSlide    // ✌️ two fingers
            case 3:  pose = .prevSlide    // 🤟 three fingers
            default: pose = nil
            }
        case .pdf:      // Everything
            switch count {
            case 0:  pose = .scrollDown   // ✊ fist
            case 1:  pose = .scrollUp     // ☝️ one finger
            case 2:  pose = .nextSlide    // ✌️ two fingers
            case 3:  pose = .prevSlide    // 🤟 three fingers
            default: pose = nil
            }
        }
        guard let g = pose else { pendingPose = nil; return }

        // Debounce: the pose must persist before it triggers, so transitions
        // (e.g. ✋ → ✊ passing through 3/2/1 fingers) don't mis-fire.
        // Next/Previous need a longer, deliberate hold; the fill toward firing is
        // published as `pinchProgress` so companions can render a countdown ring.
        if g != pendingPose {
            pendingPose = g
            poseSince = now
            firedThisHold = false   // a new pose starts a fresh hold
            return
        }
        let needed = isRepeating(g) ? poseStableTime : navPoseStableTime
        if !isRepeating(g) && !firedThisHold {
            pinchProgress = min(1, CGFloat(now.timeIntervalSince(poseSince) / needed))
        }
        guard now.timeIntervalSince(poseSince) >= needed else { return }

        if isRepeating(g) {
            // Scroll: the cooldown turns a held pose into a steady repeat.
            fire(g, now: now)
        } else if !firedThisHold && now.timeIntervalSince(lastNavFire) >= navCooldown {
            // Next/Previous: once per hold AND never within `navCooldown`.
            fire(g, now: now, ignoreCooldown: true)
            firedThisHold = true
            lastNavFire = now
            pinchProgress = 0
        }
    }

    private func fire(_ g: Gesture, now: Date,
                      ignoreCooldown: Bool = false,
                      ignoreArmed: Bool = false) {
        if !ignoreArmed && !armed { return }
        if !ignoreCooldown && now.timeIntervalSince(lastFire) < cooldown { return }
        lastFire = now
        DispatchQueue.main.async { self.onGesture?(g) }
    }

    func reset() {
        armed = false
        pendingPose = nil
        firedThisHold = false
        pinchAnchorY = nil
        oneFingerSince = nil
        pinchProgress = 0
    }
}
