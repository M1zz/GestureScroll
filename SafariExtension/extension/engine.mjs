// engine.mjs — the only ES module. Wraps MediaPipe Tasks Vision so content.js
// (a classic content script) can create a hand landmarker from bundled, fully
// local assets. No network access at runtime.
import { FilesetResolver, HandLandmarker } from "./lib/vision_bundle.mjs";

// `base` is the extension resource root (runtime.getURL('')), passed in from
// content.js so this module doesn't need the extension API directly.
export async function createHandLandmarker(base) {
  const fileset = await FilesetResolver.forVisionTasks(base + "wasm");
  const landmarker = await HandLandmarker.createFromOptions(fileset, {
    baseOptions: {
      modelAssetPath: base + "model/hand_landmarker.task",
      delegate: "GPU",
    },
    runningMode: "VIDEO",
    numHands: 1,
    minHandDetectionConfidence: 0.4,
    minHandPresenceConfidence: 0.4,
    minTrackingConfidence: 0.4,
  });
  return landmarker;
}
