import Foundation
import Combine
import AVFoundation
import AppKit
import ServiceManagement

/// Top-level coordinator: owns the camera, recognizer, and translates
/// gestures into system control actions based on the selected mode.
final class GestureEngine: ObservableObject {

    enum ControlMode: String, CaseIterable, Identifiable {
        case scroll  = "Scroll"    // web/docs — smooth scroll wheel
        case keynote = "Keynote"   // left/right arrows ONLY (ignores scroll poses)
        case pdf     = "PDF"       // all gestures → arrow keys
        case cursor  = "Mouse"     // hand steers the pointer, pinch = click/drag
        var id: String { rawValue }
    }

    let camera = HandPoseCamera()
    let broadcaster = StatusBroadcaster()      // streams status to iPhone/Watch
    private let recognizer = GestureRecognizer()
    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    /// Current state as a portable snapshot (for the menu bar + companion devices).
    var status: GestureStatus {
        let edge: GestureStatus.Edge? = edgeHint.map {
            switch $0.arrow {
            case "arrow.left":  return .left
            case "arrow.right": return .right
            case "arrow.up":    return .up
            default:            return .down
            }
        }
        let kind: GestureStatus.Kind = !enabled ? .off
            : !handVisible ? .noHand
            : pinchActive ? .pinch
            : commandActive ? .command
            : armed ? .listening : .idle
        return GestureStatus(kind: kind, edge: edge, lastGesture: lastGesture, mode: mode.rawValue,
                             navCooldown: recognizer.navCooldown, navSeq: navSeq,
                             handDetected: handVisible, handX: handX, handY: handY,
                             poseEmoji: handPose, pinchProgress: Double(recognizer.pinchProgress))
    }

    /// Bumps once per fired Next/Previous so companions can start a cooldown ring.
    private var navSeq = 0

    // Persisted user settings (restored on launch).
    private enum Pref {
        static let mode = "pref.mode"
        static let dragSensitivity = "pref.dragSensitivity"
        static let upSpeed = "pref.upSpeed"
        static let cameraID = "pref.cameraID"
    }

    @Published var enabled = false
    @Published var mode: ControlMode = .scroll {
        didSet {
            releaseCursor()               // never leave a click held across modes
            stopScrollPump()
            broadcaster.send(status)
            UserDefaults.standard.set(mode.rawValue, forKey: Pref.mode)
        }
    }
    @Published var lastGesture: String = "—"
    @Published var lastGestureTime: Date = .distantPast
    @Published var armed = false
    @Published var hasPermission = false
    @Published var cameraDenied = false        // camera permission refused in System Settings
    @Published var dragSensitivity: Int32 = 8 {  // pinch-drag DOWN: scroll amount per hand movement
        didSet { UserDefaults.standard.set(Int(dragSensitivity), forKey: Pref.dragSensitivity) }
    }
    @Published var upSpeed: Int32 = 6 {          // one-finger UP: continuous scroll speed
        didSet { UserDefaults.standard.set(Int(upSpeed), forKey: Pref.upSpeed) }
    }
    @Published var selectedCameraID: String? {
        didSet { UserDefaults.standard.set(selectedCameraID, forKey: Pref.cameraID) }
    }
    @Published var commandActive = false       // true briefly while a command fires
    @Published var pinchActive = false         // true while a scroll pinch (🤏) is recognized
    @Published var handVisible = false         // true while a hand is detected in frame
    @Published var edgeHint: EdgeHint?         // shown when the hand nears/leaves the frame edge
    private var handX: Double = 0.5            // last hand position (normalized, mirrored)
    private var handY: Double = 0.5
    private var handPose: String = ""          // current hand-shape emoji (for companions)

    /// A nudge telling the user which way to move their hand back into frame.
    struct EdgeHint: Equatable { let text: String; let arrow: String }

    /// Emoji describing the current hand shape (thumb excluded, matching the
    /// recognizer's finger count). Empty when no hand is detected.
    static func poseEmoji(_ f: HandPoseCamera.FingerExtension, detected: Bool) -> String {
        guard detected else { return "" }
        if f.pinch { return "🤏" }
        let count = [f.index, f.middle, f.ring, f.little].filter { $0 }.count
        return ["✊", "☝️", "✌️", "🤟", "✋"][min(count, 4)]
    }

    private var commandResetWork: DispatchWorkItem?
    private var lastHandPos: CGPoint?

    private var scrollAccum: Double = 0   // fractional pixels carried between frames
    private var scrollEMA: Double = 0     // smoothed per-frame delta (kills hand jitter)

    // Camera frames arrive at only ~15–30fps, far below the display refresh rate,
    // so posting one scroll event per frame reads as visible stutter. Instead the
    // frames deposit pixels into `pendingScroll` and a 120Hz pump drains it in
    // small steps, keeping motion fluid between hand-pose updates.
    private var pendingScroll: Double = 0
    private var scrollPumpTimer: Timer?

    // Cursor mode state: smoothed pointer position + press(click) edge tracking.
    private var cursorPos: CGPoint?          // smoothed, in screen coordinates
    private var cursorPressed = false        // true while the click (fist/pinch) is held
    private var pressCandidateSince: Date?   // fist must persist briefly before pressing

    init() {
        // Restore persisted settings before wiring anything up.
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Pref.mode), let m = ControlMode(rawValue: raw) {
            mode = m
        }
        if defaults.object(forKey: Pref.dragSensitivity) != nil {
            dragSensitivity = Int32(clamping: defaults.integer(forKey: Pref.dragSensitivity))
        }
        if defaults.object(forKey: Pref.upSpeed) != nil {
            upSpeed = Int32(clamping: defaults.integer(forKey: Pref.upSpeed))
        }
        selectedCameraID = defaults.string(forKey: Pref.cameraID)

        recognizer.onGesture = { [weak self] g in self?.handle(g) }
        recognizer.onScroll = { [weak self] delta in self?.handleSmoothScroll(delta) }
        recognizer.onCursor = { [weak self] pos, pinch in self?.handleCursor(pos, pinch: pinch) }

        // Drive the recognizer from camera updates.
        camera.$handDetected
            .combineLatest(camera.$indexTip, camera.$wrist, camera.$fingerExtension)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected, tip, wrist, fingers in
                guard let self else { return }
                self.recognizer.update(handDetected: detected, indexTip: tip, wrist: wrist,
                                       fingers: fingers, mode: self.mode)
                self.armed = self.recognizer.armed
                if detected != self.handVisible { self.handVisible = detected }
                if !detected { self.releaseCursor() }   // hand lost → drop any held click
                // Live pinch feedback (Scroll drag, Cursor click).
                let pinching = (self.mode == .scroll || self.mode == .cursor)
                    && self.armed && detected && fingers.pinch
                if pinching != self.pinchActive { self.pinchActive = pinching }
                // Live hand position + shape for the companion display. Round to
                // ~1% so tiny jitter doesn't defeat the broadcaster's dedup.
                if let p = wrist ?? tip {
                    self.handX = (p.x * 100).rounded() / 100
                    self.handY = (p.y * 100).rounded() / 100
                }
                self.handPose = Self.poseEmoji(fingers, detected: detected)
                self.updateEdgeHint(detected: detected, pos: tip ?? wrist)
                self.broadcaster.send(self.status)   // stream to iPhone/Watch
            }
            .store(in: &cancellables)

        hasPermission = SystemControl.hasAccessibilityPermission()
        startPermissionMonitoring()
    }

    deinit {
        permissionTimer?.invalidate()
        scrollPumpTimer?.invalidate()
    }

    /// Re-check the Accessibility permission periodically so the warning banner
    /// disappears as soon as the permission is present — e.g. right after launch
    /// (AXIsProcessTrusted can briefly report false at startup) or after the user
    /// grants it in System Settings. Once granted, the banner won't show again.
    private func startPermissionMonitoring() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
    }

    func refreshPermission() {
        let granted = SystemControl.hasAccessibilityPermission()
        if granted != hasPermission { hasPermission = granted }
    }

    func requestPermission() {
        SystemControl.requestAccessibilityPermission()
        // Re-check shortly after; the user may grant it in System Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshPermission() }
    }

    func toggle() {
        if enabled {
            enabled = false
            camera.stop()
            recognizer.reset()
            releaseCursor()
            stopScrollPump()
            edgeHint = nil
            lastHandPos = nil
            broadcaster.send(status)
            return
        }

        // Turning on: make sure we're allowed to use the camera first, so a
        // denied permission shows a clear banner instead of a silent black view.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.startCapture() } else { self.cameraDenied = true }
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func startCapture() {
        cameraDenied = false
        enabled = true
        let device = camera.availableCameras.first { $0.uniqueID == selectedCameraID }
        camera.start(device: device)
        broadcaster.send(status)
    }

    // MARK: - Launch at login (SMAppService, macOS 13+)

    /// Whether the app is registered to start automatically at login.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration can fail (e.g. app not in /Applications during dev);
                // the toggle simply reflects the real status on next read.
            }
            objectWillChange.send()
        }
    }

    /// Opens the Camera privacy pane so the user can re-grant a denied permission.
    func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func selectCamera(_ id: String?) {
        selectedCameraID = id
        if enabled {
            let device = camera.availableCameras.first { $0.uniqueID == id }
            camera.start(device: device)
        }
    }

    /// Smooth, drag-proportional scrolling for the pinch-drag. `delta` is the
    /// per-frame normalized hand movement (positive = downward).
    /// A light EMA keeps the page glued to the hand while filtering out the
    /// per-frame jitter of the pose estimate (which read as "loose" scrolling).
    private func handleSmoothScroll(_ delta: CGFloat) {
        guard SystemControl.hasAccessibilityPermission() else {
            hasPermission = false
            return
        }
        scrollEMA = scrollEMA * 0.45 + Double(delta) * 0.55
        guard abs(scrollEMA) > 0.0008 else { return }   // deadzone: ignore tremor
        // Down (positive) uses drag sensitivity; up (negative) uses up speed.
        let strength = scrollEMA > 0 ? dragSensitivity : upSpeed
        pendingScroll += scrollEMA * Double(strength) * 420.0
        startScrollPump()
        lastGesture = (pendingScroll > 0 ? Gesture.scrollDown : Gesture.scrollUp).rawValue
        pulseCommand()
    }

    private func startScrollPump() {
        guard scrollPumpTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.pumpScroll()
        }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        scrollPumpTimer = t
    }

    /// One 120Hz tick: drain a fraction of the pending pixels (exponential glide —
    /// tracks the hand closely but settles within ~30ms once it stops).
    private func pumpScroll() {
        let step = pendingScroll * 0.35
        pendingScroll -= step
        scrollAccum += step
        let whole = Int32(scrollAccum)
        if whole != 0 {
            scrollAccum -= Double(whole)
            SystemControl.scrollPixels(down: whole)
        }
        if abs(pendingScroll) < 0.5 {
            pendingScroll = 0
            scrollPumpTimer?.invalidate()
            scrollPumpTimer = nil
        }
    }

    /// Drop any queued scroll motion (mode switch / off / hand lost).
    private func stopScrollPump() {
        scrollPumpTimer?.invalidate()
        scrollPumpTimer = nil
        pendingScroll = 0
        scrollAccum = 0
        scrollEMA = 0
    }

    /// Cursor mode: map the normalized hand position to the main display and drive
    /// the pointer. The inner 70% of the frame maps to the full screen (so the hand
    /// never has to chase the frame edges) and an EMA smooths tracking.
    /// Click = 🤏 pinch (thumb tip to index tip); releasing the pinch lets go — so
    /// pinch-release is a click and moving while pinched is a drag. The pinch must
    /// persist a beat before pressing, so pose transitions can't fire phantom
    /// clicks; release is immediate (releasing is always safe).
    private func handleCursor(_ pos: CGPoint, pinch pressing: Bool) {
        guard SystemControl.hasAccessibilityPermission() else {
            hasPermission = false
            return
        }
        let margin: CGFloat = 0.15
        let u = min(max((pos.x - margin) / (1 - 2 * margin), 0), 1)
        let v = min(max((pos.y - margin) / (1 - 2 * margin), 0), 1)
        let screen = SystemControl.mainDisplaySize
        let target = CGPoint(x: u * screen.width, y: v * screen.height)

        // Smooth toward the target — tight enough to feel 1:1, calm enough not to shake.
        let alpha: CGFloat = 0.45
        let p: CGPoint
        if let last = cursorPos {
            p = CGPoint(x: last.x + (target.x - last.x) * alpha,
                        y: last.y + (target.y - last.y) * alpha)
        } else {
            p = target
        }
        cursorPos = p

        if pressing {
            if cursorPressed {
                SystemControl.moveMouse(to: p, dragging: true)     // pinch held → drag
            } else {
                if pressCandidateSince == nil { pressCandidateSince = Date() }
                if Date().timeIntervalSince(pressCandidateSince!) >= 0.12 {
                    cursorPressed = true                            // debounced → press
                    SystemControl.mouseDown(at: p)
                    lastGesture = "Click 🤏"
                    pulseCommand()
                } else {
                    SystemControl.moveMouse(to: p)                  // not confirmed yet
                }
            }
        } else {
            pressCandidateSince = nil
            if cursorPressed {
                cursorPressed = false                               // pinch released → let go
                SystemControl.mouseUp(at: p)
                lastGesture = "Release 🖐"
                pulseCommand()
            } else {
                SystemControl.moveMouse(to: p)
            }
        }
    }

    /// Release any held click and forget cursor state (mode switch / off / hand lost).
    private func releaseCursor() {
        if cursorPressed, let p = cursorPos { SystemControl.mouseUp(at: p) }
        cursorPressed = false
        pressCandidateSince = nil
        cursorPos = nil
    }

    /// Update the edge-recovery hint. While the hand is visible we warn as it nears
    /// an edge; once it's lost we point back from the edge it likely exited.
    private func updateEdgeHint(detected: Bool, pos: CGPoint?) {
        guard enabled else { if edgeHint != nil { edgeHint = nil }; return }
        let hint: EdgeHint?
        if detected, let p = pos {
            lastHandPos = p
            hint = edgeHintFor(p, margin: 0.15)        // proactive: nearing an edge
        } else {
            hint = lastHandPos.flatMap { edgeHintFor($0, margin: 0.30) }  // lost near an edge
        }
        if hint != edgeHint { edgeHint = hint }
    }

    private func edgeHintFor(_ p: CGPoint, margin: CGFloat) -> EdgeHint? {
        let dRight = 1 - p.x, dLeft = p.x, dTop = p.y, dBottom = 1 - p.y
        let minD = min(dRight, dLeft, dTop, dBottom)
        guard minD <= margin else { return nil }
        if minD == dRight { return EdgeHint(text: "손을 왼쪽으로", arrow: "arrow.left") }
        if minD == dLeft  { return EdgeHint(text: "손을 오른쪽으로", arrow: "arrow.right") }
        if minD == dTop   { return EdgeHint(text: "손을 아래로", arrow: "arrow.down") }
        return EdgeHint(text: "손을 위로", arrow: "arrow.up")
    }

    /// Briefly light up the "command active" indicator (menu-bar / UI feedback).
    private func pulseCommand() {
        commandActive = true
        commandResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commandActive = false }
        commandResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func handle(_ g: Gesture) {
        lastGesture = g.rawValue
        lastGestureTime = Date()

        guard SystemControl.hasAccessibilityPermission() else {
            hasPermission = false
            return
        }

        if g != .activate { pulseCommand() }

        // A fired Next/Previous starts the nav cooldown — bump the sequence so the
        // companion app can begin its depleting cooldown ring, and push immediately.
        if g == .nextSlide || g == .prevSlide {
            navSeq &+= 1
            broadcaster.send(status)
        }

        switch (mode, g) {
        // Scroll (web/docs) — handled continuously via handleSmoothScroll (pinch
        // drag + one-finger up); discrete gestures aren't emitted in this mode.
        case (.scroll, _):
            break

        // Cursor — handled continuously via handleCursor (move/click/drag);
        // discrete gestures aren't emitted in this mode.
        case (.cursor, _):
            break

        // Keynote — ONLY left/right via the dedicated Next/Previous poses.
        // Scroll poses (1/2 fingers) are intentionally ignored so a stray finger
        // count can't change slides mid-presentation.
        case (.keynote, .nextSlide):
            SystemControl.pressKey(SystemControl.kRightArrow)
        case (.keynote, .prevSlide):
            SystemControl.pressKey(SystemControl.kLeftArrow)
        case (.keynote, .scrollDown), (.keynote, .scrollUp):
            break // ignored in Keynote

        // PDF — every gesture maps to an arrow key.
        case (.pdf, .nextSlide):
            SystemControl.pressKey(SystemControl.kRightArrow)
        case (.pdf, .prevSlide):
            SystemControl.pressKey(SystemControl.kLeftArrow)
        case (.pdf, .scrollDown):
            SystemControl.pressKey(SystemControl.kDownArrow)
        case (.pdf, .scrollUp):
            SystemControl.pressKey(SystemControl.kUpArrow)

        case (_, .activate):
            break // just a feedback event
        }
    }
}
