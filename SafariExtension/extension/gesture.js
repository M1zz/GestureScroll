// gesture.js — pure gesture logic, no DOM, no MediaPipe.
// Faithful port of the macOS app's GestureRecognizer.swift and the finger-
// extension math in HandPoseCamera.swift. Runs in the content-script world;
// content.js consumes the classes/functions declared here at top level.

// ---------------------------------------------------------------------------
// Finger extension from MediaPipe hand landmarks (21 points, normalized 0..1).
//
// MediaPipe landmark indices used:
//   0 wrist · 4 thumbTip · 5/6/8 index MCP/PIP/Tip · 9/10/12 middle ·
//   13/14/16 ring · 17/18/20 little
//
// We mirror X (selfie feel) and keep Y as-is so the recognizer's directional
// logic matches the native app. Distances are mirror-invariant, so the
// extension/pinch tests are unaffected by the transform either way.
// ---------------------------------------------------------------------------
function fingersFromLandmarks(lm) {
  const P = (i) => ({ x: 1 - lm[i].x, y: lm[i].y });
  const wrist = P(0);
  const d = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

  // A finger is "extended" only when its tip is clearly beyond the knuckle (MCP)
  // measured from the wrist, AND not folded back past its PIP joint.
  function extended(tipI, pipI, mcpI) {
    const t = P(tipI), m = P(mcpI);
    const knuckle = d(m, wrist);
    if (knuckle <= 0.01) return false;
    const p = P(pipI);
    if (d(t, wrist) < d(p, wrist)) return false; // curled
    return d(t, wrist) > knuckle * 1.2;
  }

  const index  = extended(8, 6, 5);
  const middle = extended(12, 10, 9);
  const ring   = extended(16, 14, 13);
  const little = extended(20, 18, 17);
  // Thumb is intentionally NOT counted (least reliable joint), matching native.

  // Pinch: thumb tip and index tip close together, relative to palm size.
  const thumbT = P(4), idxT = P(8), idxMCP = P(5);
  const palm = d(wrist, idxMCP);
  const pinch = palm > 0.01 && d(thumbT, idxT) < palm * 0.6;

  return { index, middle, ring, little, pinch, wrist, indexTip: idxT };
}

// Temporal majority voting over recent frames, so one mis-read frame can't flip
// the detected pose. Mirrors HandPoseCamera's 5-frame vote.
class FingerVoter {
  constructor(window = 5) { this.window = window; this.history = []; }
  reset() { this.history = []; }
  vote(f) {
    this.history.push(f);
    if (this.history.length > this.window) this.history.shift();
    const h = this.history;
    const maj = (key) => h.filter(key).length * 2 > h.length;
    return {
      index:  maj((x) => x.index),
      middle: maj((x) => x.middle),
      ring:   maj((x) => x.ring),
      little: maj((x) => x.little),
      pinch:  maj((x) => x.pinch),
      wrist:  f.wrist,       // position uses the latest frame (not voted)
      indexTip: f.indexTip,
    };
  }
}

// A short emoji describing the current hand shape, for the on-screen readout
// and the companion display.
function poseEmoji(f) {
  if (!f) return "";
  if (f.pinch) return "🤏";
  const count = [f.index, f.middle, f.ring, f.little].filter(Boolean).length;
  return ["✊", "☝️", "✌️", "🤟", "✋"][count] || "🖐";
}

// ---------------------------------------------------------------------------
// GestureRecognizer — port of GestureRecognizer.swift. Times are in seconds
// (performance.now()/1000). Modes: 'scroll' | 'keynote' | 'pdf'.
//
//   scroll:  ✊/pinch-drag → smooth scroll down · ☝️ one finger → scroll up
//   keynote: 🤏 pinch-hold 3s = Next · ✊ pump (쥐폈쥐폈) = Previous
//   pdf:     ✊=down · ☝️=up · ✌️=Next · 🤟=Previous
//
// Safety: an open palm (✋) must arm Listening first; poses debounce; Next/Prev
// fire once per hold with a hard navCooldown floor.
// ---------------------------------------------------------------------------
class GestureRecognizer {
  constructor() {
    this.onGesture = null;   // (gesture: string) => void  — discrete events
    this.onScroll  = null;   // (delta: number) => void     — smooth scroll (+ = down)

    // Tunables (seconds / normalized), identical to the Swift defaults.
    this.cooldown = 0.7;
    this.poseStableTime = 0.25;
    this.armWindow = 6.0;
    this.navCooldown = 4.0;
    this.openStableTime = 0.35;
    this.upScrollRate = 0.010;
    this.pinchHoldForNext = 1.5;   // hold a pinch (🤏) this long → Keynote "Next"
    this.pumpWindow = 2.0;
    this.pumpClenchesForPrev = 2;

    this._reset(true);
  }

  _reset(hard) {
    this.armed = false;
    this.armedUntil = -1e9;
    this.lastFire = -1e9;
    this.pendingPose = null;
    this.poseSince = -1e9;
    this.firedThisHold = false;
    this.lastNavFire = -1e9;
    this.openSince = null;
    this.pinchAnchorY = null;
    this.oneFingerSince = null;
    this.pinchHoldStart = null;
    this.pinchFiredThisHold = false;
    this.pinchProgress = 0;   // 0..1 fill of the Keynote pinch-hold toward "Next"
    this.pumpWasOpen = false;
    this.clenchTimes = [];
    if (hard) { /* nothing extra */ }
  }

  reset() { this._reset(true); }

  isRepeating(g) { return g === "scrollUp" || g === "scrollDown"; }

  update(handDetected, f, mode) {
    const now = performance.now() / 1000;

    if (this.armed && now > this.armedUntil) this.armed = false;

    if (!handDetected) {
      this.pendingPose = null;
      this.firedThisHold = false;
      this.openSince = null;
      this.pinchAnchorY = null;
      this.oneFingerSince = null;
      this.pinchHoldStart = null;
      this.pinchFiredThisHold = false;
      this.pinchProgress = 0;
      this.pumpWasOpen = false;
      this.clenchTimes = [];
      return;
    }

    const count = [f.index, f.middle, f.ring, f.little].filter(Boolean).length;

    // --- Open hand (✋): arm Listening; prime the open→fist Keynote pump. ---
    if (count >= 4) {
      this.pumpWasOpen = true;
      if (!this.armed) {
        this.armed = true;
        this._fire("activate", now, true, true);
      }
      if (this.openSince == null) this.openSince = now;
      this.armedUntil = now + this.armWindow;
      this.pendingPose = null;
      this.firedThisHold = false;
      this.pinchHoldStart = null;
      this.pinchFiredThisHold = false;
      this.pinchProgress = 0;
      return;
    }
    this.openSince = null;
    this.pinchProgress = 0;   // default; the Keynote pinch-hold path sets it below

    if (!this.armed) return;

    // Keep armed while actively posing.
    this.armedUntil = now + this.armWindow;

    // --- Keynote navigation ---
    if (mode === "keynote") {
      // Previous: count open→fist clenches within the window (쥐폈쥐폈).
      const isFist = count === 0 && !f.pinch;
      if (isFist && this.pumpWasOpen) {
        this.clenchTimes.push(now);
        this.pumpWasOpen = false;
      }
      this.clenchTimes = this.clenchTimes.filter((t) => now - t <= this.pumpWindow);
      if (this.clenchTimes.length >= this.pumpClenchesForPrev &&
          now - this.lastNavFire >= this.navCooldown) {
        this._fire("prevSlide", now, true);
        this.lastNavFire = now;
        this.clenchTimes = [];
      }

      // Next: HOLD a pinch (🤏) for pinchHoldForNext seconds. pinchProgress (0..1)
      // fills a ring; when it completes, "Next" fires once per continuous hold.
      if (f.pinch) {
        if (this.pinchHoldStart == null) { this.pinchHoldStart = now; this.pinchFiredThisHold = false; }
        const held = now - this.pinchHoldStart;
        this.pinchProgress = Math.min(1, held / this.pinchHoldForNext);
        if (!this.pinchFiredThisHold && held >= this.pinchHoldForNext) {
          this._fire("nextSlide", now, true);
          this.lastNavFire = now;
          this.pinchFiredThisHold = true;
        }
        return;
      }
      this.pinchHoldStart = null;
      this.pinchFiredThisHold = false;
    }

    // --- Scroll mode (browser): both directions scroll smoothly ---
    if (mode === "scroll") {
      if (f.pinch && f.wrist) {
        const y = f.wrist.y;
        if (this.pinchAnchorY != null) {
          const dy = this.pinchAnchorY - y;   // +dy = hand moved up → scroll down
          if (dy !== 0 && this.onScroll) this.onScroll(dy); // bidirectional grab-drag
        }
        this.pinchAnchorY = y;
        this.oneFingerSince = null;
        return;
      }
      this.pinchAnchorY = null;
      if (count === 1) {                       // one finger → smooth scroll up
        if (this.oneFingerSince == null) this.oneFingerSince = now;
        if (now - this.oneFingerSince >= this.poseStableTime && this.onScroll) {
          this.onScroll(-this.upScrollRate);
        }
      } else {
        this.oneFingerSince = null;
      }
      return;
    }

    // --- Pose → semantic gesture, per mode (Keynote fires nothing here / PDF all) ---
    let pose = null;
    if (mode === "pdf") {
      switch (count) {
        case 0: pose = "scrollDown"; break; // ✊
        case 1: pose = "scrollUp";   break; // ☝️
        case 2: pose = "nextSlide";  break; // ✌️
        case 3: pose = "prevSlide";  break; // 🤟
        default: pose = null;
      }
    }
    if (pose == null) { this.pendingPose = null; return; }

    // Debounce: a pose must persist before triggering.
    if (pose !== this.pendingPose) {
      this.pendingPose = pose;
      this.poseSince = now;
      this.firedThisHold = false;
      return;
    }
    if (now - this.poseSince < this.poseStableTime) return;

    if (this.isRepeating(pose)) {
      this._fire(pose, now);
    } else if (!this.firedThisHold && now - this.lastNavFire >= this.navCooldown) {
      this._fire(pose, now, true);
      this.firedThisHold = true;
      this.lastNavFire = now;
    }
  }

  _fire(g, now, ignoreCooldown = false, ignoreArmed = false) {
    if (!ignoreArmed && !this.armed) return;
    if (!ignoreCooldown && now - this.lastFire < this.cooldown) return;
    this.lastFire = now;
    if (this.onGesture) this.onGesture(g);
  }
}
