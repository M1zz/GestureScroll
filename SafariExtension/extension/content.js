// content.js — injects the floating panel, runs the camera + hand-detection
// loop, feeds the ported GestureRecognizer, and applies actions (scroll / arrow
// keys) to THIS page. Classes from gesture.js are in scope (same content world).

const api = globalThis.browser ?? globalThis.chrome;

const state = {
  running: false,
  mode: "scroll",       // 'scroll' | 'keynote' | 'pdf'
  sensitivity: 8,       // scroll strength (matches native dragSensitivity default)
  video: null,
  stream: null,
  landmarker: null,
  recognizer: null,
  voter: null,
  raf: 0,
  scrollAccum: 0,
  lastPose: "",
  armed: false,
};

// ---------------------------------------------------------------------------
// Panel UI
// ---------------------------------------------------------------------------
let ui = null;

function buildPanel() {
  if (ui) return ui;
  const root = document.createElement("div");
  root.id = "gs-panel";
  root.innerHTML = `
    <div class="gs-head">
      <span class="gs-title">GestureScroll</span>
      <button class="gs-close" title="닫기">×</button>
    </div>
    <div class="gs-preview"><video autoplay playsinline muted></video>
      <div class="gs-pose">—</div>
    </div>
    <div class="gs-bar"><div class="gs-bar-fill"></div></div>
    <button class="gs-toggle">시작</button>
    <label class="gs-row">모드
      <select class="gs-mode">
        <option value="scroll">Scroll (웹 스크롤)</option>
        <option value="keynote">Slides (←/→ 발표)</option>
        <option value="pdf">PDF (전체 화살표)</option>
      </select>
    </label>
    <label class="gs-row">감도 <input class="gs-sens" type="range" min="2" max="20" step="1"></label>
    <div class="gs-status">꺼짐</div>
  `;
  document.documentElement.appendChild(root);

  ui = {
    root,
    video: root.querySelector("video"),
    pose: root.querySelector(".gs-pose"),
    barFill: root.querySelector(".gs-bar-fill"),
    toggle: root.querySelector(".gs-toggle"),
    mode: root.querySelector(".gs-mode"),
    sens: root.querySelector(".gs-sens"),
    status: root.querySelector(".gs-status"),
    close: root.querySelector(".gs-close"),
  };
  state.video = ui.video;

  ui.mode.value = state.mode;
  ui.sens.value = String(state.sensitivity);

  ui.toggle.addEventListener("click", () => (state.running ? stop() : start()));
  ui.mode.addEventListener("change", () => {
    state.mode = ui.mode.value;
    save();
    if (state.recognizer) state.recognizer.reset();
    setStatus();
  });
  ui.sens.addEventListener("input", () => {
    state.sensitivity = parseInt(ui.sens.value, 10);
    save();
  });
  ui.close.addEventListener("click", () => { stop(); root.remove(); ui = null; });
  return ui;
}

function setStatus(msg) {
  if (!ui) return;
  if (msg) { ui.status.textContent = msg; return; }
  if (!state.running) { ui.status.textContent = "꺼짐"; return; }
  ui.status.textContent = state.armed ? "Listening ✋ — 동작 인식 중" : "손바닥 ✋ 을 들어 시작";
}

// ---------------------------------------------------------------------------
// Camera + detection loop
// ---------------------------------------------------------------------------
async function start() {
  buildPanel();
  if (state.running) return;
  setStatus("카메라 준비 중…");
  ui.toggle.disabled = true;
  try {
    state.stream = await navigator.mediaDevices.getUserMedia({
      video: { width: 640, height: 480, facingMode: "user" },
      audio: false,
    });
    state.video.srcObject = state.stream;
    await state.video.play();

    if (!state.landmarker) {
      const mod = await import(api.runtime.getURL("engine.mjs"));
      state.landmarker = await mod.createHandLandmarker(api.runtime.getURL(""));
    }
    state.recognizer = state.recognizer || new GestureRecognizer();
    state.recognizer.onScroll = onScroll;
    state.recognizer.onGesture = onGesture;
    state.voter = new FingerVoter(5);

    state.running = true;
    ui.toggle.textContent = "중지";
    ui.toggle.disabled = false;
    ui.root.classList.add("gs-on");
    setStatus();
    loop();
  } catch (e) {
    console.error("[GestureScroll]", e);
    ui.toggle.disabled = false;
    setStatus("카메라 권한이 필요합니다");
  }
}

function stop() {
  state.running = false;
  if (state.raf) cancelAnimationFrame(state.raf);
  state.raf = 0;
  if (state.stream) { state.stream.getTracks().forEach((t) => t.stop()); state.stream = null; }
  if (state.video) state.video.srcObject = null;
  if (state.recognizer) state.recognizer.reset();
  if (state.voter) state.voter.reset();
  state.armed = false;
  if (ui) {
    ui.toggle.textContent = "시작";
    ui.root.classList.remove("gs-on");
    ui.pose.textContent = "—";
  }
  setStatus();
}

let lastTs = -1;
function loop() {
  if (!state.running) return;
  const v = state.video;
  if (v && v.readyState >= 2) {
    const ts = performance.now();
    if (ts !== lastTs) {
      lastTs = ts;
      let handDetected = false;
      let fingers = null;
      try {
        const res = state.landmarker.detectForVideo(v, ts);
        if (res && res.landmarks && res.landmarks.length > 0) {
          handDetected = true;
          const raw = fingersFromLandmarks(res.landmarks[0]);
          fingers = state.voter.vote(raw);
        } else {
          state.voter.reset();
        }
      } catch (e) { /* ignore per-frame failures */ }

      state.recognizer.update(handDetected, fingers, state.mode);
      state.armed = state.recognizer.armed;

      // Live readout: hand shape emoji positioned over the preview.
      if (handDetected && fingers) {
        ui.pose.textContent = poseEmoji(fingers);
        // wrist is in mirrored/top-left coords (0..1) — place the emoji there.
        ui.pose.style.left = (fingers.wrist.x * 100) + "%";
        ui.pose.style.top = (fingers.wrist.y * 100) + "%";
        ui.pose.style.opacity = "1";
      } else {
        ui.pose.style.opacity = "0.25";
      }
      // Keynote pinch-hold fill (mirrors the iPhone ring).
      const prog = state.recognizer.pinchProgress || 0;
      ui.barFill.style.width = (prog * 100) + "%";
      ui.barFill.parentElement.style.opacity = prog > 0 ? "1" : "0";
      setStatus();
    }
  }
  state.raf = requestAnimationFrame(loop);
}

// ---------------------------------------------------------------------------
// Page actions
// ---------------------------------------------------------------------------
let scrollEMA = 0;
function onScroll(delta) {
  // delta: per-frame normalized hand motion (+ = down). EMA keeps the page glued
  // to the hand while filtering pose jitter (matches the native app's feel).
  scrollEMA = scrollEMA * 0.45 + delta * 0.55;
  if (Math.abs(scrollEMA) <= 0.0008) return;   // deadzone: ignore tremor
  const strength = scrollEMA > 0 ? state.sensitivity : Math.max(2, state.sensitivity - 2);
  state.scrollAccum += scrollEMA * strength * 420;
  const whole = Math.trunc(state.scrollAccum);
  if (whole === 0) return;
  state.scrollAccum -= whole;
  window.scrollBy(0, whole);
}

const KEY = { ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40 };
function pressKey(key) {
  const target = document.activeElement || document.body;
  for (const type of ["keydown", "keyup"]) {
    target.dispatchEvent(new KeyboardEvent(type, {
      key, code: key, keyCode: KEY[key], which: KEY[key],
      bubbles: true, cancelable: true,
    }));
  }
}

function onGesture(g) {
  if (g === "activate") return; // just arms Listening
  if (state.mode === "keynote") {
    if (g === "nextSlide") pressKey("ArrowRight");
    else if (g === "prevSlide") pressKey("ArrowLeft");
  } else if (state.mode === "pdf") {
    if (g === "nextSlide") pressKey("ArrowRight");
    else if (g === "prevSlide") pressKey("ArrowLeft");
    else if (g === "scrollDown") pressKey("ArrowDown");
    else if (g === "scrollUp") pressKey("ArrowUp");
  }
  if (ui) { ui.status.textContent = "동작: " + g; }
}

// ---------------------------------------------------------------------------
// Settings persistence + popup messaging
// ---------------------------------------------------------------------------
function save() {
  try { api.storage?.local.set({ mode: state.mode, sensitivity: state.sensitivity }); } catch {}
}
async function load() {
  try {
    const s = await api.storage?.local.get(["mode", "sensitivity"]);
    if (s?.mode) state.mode = s.mode;
    if (s?.sensitivity) state.sensitivity = s.sensitivity;
  } catch {}
}

api.runtime?.onMessage?.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "toggle") { state.running ? stop() : start(); sendResponse?.({ running: state.running }); }
  else if (msg?.type === "status") { sendResponse?.({ running: state.running, mode: state.mode }); }
  else if (msg?.type === "setMode") { state.mode = msg.mode; if (ui) ui.mode.value = msg.mode; save(); }
  return true;
});

// Build the (collapsed) panel on load so the user always has a control, but do
// not touch the camera until they press 시작.
(async () => {
  await load();
  buildPanel();
  setStatus();
})();
