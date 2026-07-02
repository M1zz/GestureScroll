# GestureScroll

Control the frontmost macOS app (Safari, Keynote, PDF, etc.) with hand gestures
seen through your camera. Built for the "laptop on the table facing the presenter,
mirror the screen, wave to scroll" use case.

## Pipeline

```
Camera (AVCaptureSession)
  → Vision VNDetectHumanHandPoseRequest   (per frame, 21 joints)
  → GestureRecognizer                     (arm/cooldown state machine)
  → SystemControl (CGEvent)               (scroll wheel / arrow keys)
  → frontmost app scrolls
```

Because the screen you mirror to a projector is just a mirror of *this* Mac,
controlling the frontmost Safari here controls what the audience sees.

## Requirements

- macOS 13+
- Xcode 15+
- A camera (built-in or external — external webcam recommended for presentations)

## Build & run

1. Open `GestureScroll.xcodeproj` in Xcode.
2. Set your own Team under Signing & Capabilities (Automatic signing).
3. Build & Run (⌘R).

## Permissions (both required)

1. **Camera** — prompted on first launch.
2. **Accessibility** — System Settings ▸ Privacy & Security ▸ Accessibility ▸
   enable GestureScroll. The in-app banner has a "Grant" button that opens the
   prompt. This is what lets the app post scroll/key events to other apps.

> The app **must not be sandboxed** (it already ships with the sandbox entitlement
> set to false). CGEvent posting to other applications is incompatible with the App
> Sandbox, so this app is for **Developer ID / direct distribution**, not the App Store.

## How to use

1. Toggle the switch to **On**. Pick your camera.
2. Choose a mode:
   - **Scroll** — swipes become smooth scroll wheel events (web pages, docs).
   - **Slides** — swipes become arrow-key presses (Keynote, Preview PDF).
3. Raise an **open palm ✋** toward the camera → the app enters *Listening* mode
   (green badge). This prevents accidental scrolls from normal presenting gestures.
4. With one **index finger 👆** up, swipe:
   - **down** → scroll down / next
   - **up** → scroll up / previous
   - **right / left** → next / previous (big jump in Scroll mode, arrow keys in Slides)
5. Listening turns off after ~4s without a palm; raise your palm again to re-arm.

## Tuning (in code)

`GestureRecognizer`:
- `cooldown` (0.9s) — min gap between fired gestures. Raise if it double-fires.
- `swipeThreshold` (0.18) — normalized travel needed. Lower = more sensitive.
- `swipeMaxDuration` (0.6s) — a swipe must complete this fast.
- `armWindow` (4.0s) — how long listening stays active after a palm.

`GestureEngine.scrollStrength` — lines per scroll gesture (UI slider too).

## Notes / limits

- Reaction has ~0.3–0.5s latency (frame processing + debounce). Fine for talks.
- Keep your hand fully in frame; edge clipping breaks tracking.
- If the hand is too small/far, joint confidence drops — use an external webcam
  with a reasonable field of view.
- Recognition is fully on-device (Vision). No network, no cloud.
```
