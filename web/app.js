/* MoveMentor 演示页
 *
 * 这个文件刻意保持"薄"：页面只做三件事——取数据、渲染、发声。
 * 「翻译成什么动作」「算不算完成一次」「屏幕上报什么数」全部由
 * MoonBit 编译出来的引擎决定（见 src/bridge）。页面里没有任何阈值、
 * 没有任何 if (reps > ...) 之类的业务判断——这是这个项目的核心主张：
 * 引擎和应用之间有真实边界，而不是把逻辑散在 UI 里。
 */

// MoonBit 的 JS 后端产物。跑 `moon build src/bridge --target js --release` 生成。
const ENGINE_URL = "../_build/js/release/build/src/bridge/bridge.js";

// MediaPipe Tasks Vision。合成模式不需要它；切到摄像头模式才会动态加载。
const MEDIAPIPE_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";

const TRACKED = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];
const BONES = [
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24],
  [23, 25], [25, 27], [24, 26], [26, 28],
];

const el = (id) => document.getElementById(id);

const state = {
  engine: null,
  motion: "jumping_jack",
  audience: "elderly_knee_pain",
  source: "synthetic",
  running: false,
  speakOn: true,
  planId: null,
  startedAt: 0,
  pendingWarmMs: 0,
  lastSpoken: -1,
  landmarker: null,
  cameraStream: null,
  rafId: 0,
  lastFrameAt: 0,
};

/* ---------- 引擎加载 ---------- */

async function loadEngine() {
  const badge = el("engine-badge");
  try {
    const engine = await import(ENGINE_URL);
    state.engine = engine;
    badge.textContent = `${engine.api_version()} · ${engine.api_motion_ids().length} 个动作 · ${engine.api_audience_ids().length} 类人群`;
    badge.classList.remove("error");
  } catch (error) {
    badge.textContent = "引擎未构建：请先在项目根目录执行 moon build src/bridge --target js --release";
    badge.classList.add("error");
    console.error(error);
  }
}

function fillSelects() {
  const engine = state.engine;
  if (!engine) return;
  const catalog = JSON.parse(engine.api_catalog_json());
  const motionSelect = el("motion");
  const audienceSelect = el("audience");
  motionSelect.innerHTML = "";
  audienceSelect.innerHTML = "";

  // 只把「源动作」列进下拉框：变式是引擎的输出，不该由用户直接选。
  catalog.motion_ids.forEach((id, index) => {
    if (catalog.motion_roles[index] !== "源动作") return;
    const option = document.createElement("option");
    option.value = id;
    option.textContent = catalog.motion_names[index];
    motionSelect.appendChild(option);
  });
  catalog.audience_ids.forEach((id, index) => {
    const option = document.createElement("option");
    option.value = id;
    option.textContent = catalog.audience_names[index];
    audienceSelect.appendChild(option);
  });
  motionSelect.value = state.motion;
  audienceSelect.value = state.audience;
}

/* ---------- 翻译与渲染 ---------- */

function applyTranslation() {
  const engine = state.engine;
  if (!engine) return;
  const raw = engine.api_translate_json(state.motion, state.audience);
  const result = JSON.parse(raw);
  if (!result.ok) {
    el("headline").textContent = "暂无可执行方案";
    el("reason").textContent = result.error;
    el("audience-tag").textContent = "—";
    return null;
  }
  state.planId = result.plan_id;
  engine.api_reset();

  el("headline").textContent = result.headline;
  el("reason").textContent = result.reason;
  el("audience-tag").textContent = result.audience_name;
  el("counter-label").textContent = result.is_hold_only ? "保持时间（秒）" : "完成次数";
  el("reps").textContent = result.is_hold_only ? "0″" : "0";
  el("phase").textContent = result.phase_ids.length ? `相位：${result.phase_ids.join(" → ")}` : "—";

  el("cues").innerHTML = "";
  result.cues.forEach((cue) => {
    const li = document.createElement("li");
    li.textContent = cue;
    el("cues").appendChild(li);
  });

  el("checks").innerHTML = "";
  result.checks.forEach((check) => {
    const li = document.createElement("li");
    li.textContent = check;
    el("checks").appendChild(li);
  });

  const script = JSON.parse(engine.api_script_json(state.motion, state.audience, 20));
  el("script").innerHTML = "";
  (script.lines || []).forEach((line) => {
    const li = document.createElement("li");
    li.textContent = line;
    el("script").appendChild(li);
  });

  const reverse = JSON.parse(engine.api_reverse_json(state.planId));
  el("reverse").textContent = reverse.source_names.length
    ? `「${result.plan_name}」同时是「${reverse.source_names.join("」「")}」的低冲击变式。同一个变式服务多个动作，说明这背后是一张可双向查询的规则表，而不是一对一写死的特例。`
    : "这是源动作，不是任何动作的变式。";

  return result;
}

/* ---------- 姿态来源 ---------- */

async function startCamera() {
  const video = el("video");
  if (!state.cameraStream) {
    state.cameraStream = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 480 } });
    video.srcObject = state.cameraStream;
    await video.play();
  }
  if (!state.landmarker) {
    el("source-note").textContent = "正在加载 MediaPipe 姿态模型（需要网络）…";
    const vision = await import(`${MEDIAPIPE_URL}/vision_bundle.mjs`);
    const fileset = await vision.FilesetResolver.forVisionTasks(`${MEDIAPIPE_URL}/wasm`);
    state.landmarker = await vision.PoseLandmarker.createFromOptions(fileset, {
      baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
      runningMode: "VIDEO",
      numPoses: 1,
    });
  }
  el("source-note").textContent = "摄像头 + MediaPipe：推理在浏览器本地完成，视频不出设备";
}

function stopCamera() {
  if (state.cameraStream) {
    state.cameraStream.getTracks().forEach((track) => track.stop());
    state.cameraStream = null;
  }
}

/** 合成模式：每帧都问引擎要一组关键点。 */
function syntheticLandmarks(now) {
  return state.engine.api_synth_landmarks(state.motion, state.audience, now);
}

/** 摄像头模式：MediaPipe 输出摊平成 132 个数，交给引擎。 */
function cameraLandmarks(now) {
  const video = el("video");
  const result = state.landmarker.detectForVideo(video, now);
  if (!result || !result.landmarks || result.landmarks.length === 0) return null;
  const flat = new Array(33 * 4).fill(0);
  result.landmarks[0].forEach((point, index) => {
    flat[index * 4] = point.x;
    flat[index * 4 + 1] = point.y;
    flat[index * 4 + 2] = point.z || 0;
    flat[index * 4 + 3] = point.visibility === undefined ? 1 : point.visibility;
  });
  return flat;
}

/* ---------- 渲染数字 ---------- */

function renderState(snapshot) {
  const isHold = snapshot.is_hold_only;
  el("reps").textContent = isHold ? `${Math.floor(snapshot.held_ms / 1000)}″` : String(snapshot.reps);
  el("progress").style.width = `${Math.round(snapshot.progress * 100)}%`;

  const confidence = el("confidence");
  const percent = Math.round(snapshot.confidence * 100);
  if (snapshot.low_confidence) {
    confidence.textContent = `关键点可见度 ${percent}% — 太低，本帧不计入`;
    confidence.classList.add("warn");
  } else {
    confidence.textContent = `关键点可见度 ${percent}%`;
    confidence.classList.remove("warn");
  }

  if (snapshot.ok && snapshot.phase_id) {
    el("phase").textContent = `当前相位：${snapshot.phase_id}`;
  }

  if (snapshot.event === "rep" || snapshot.event === "hold") {
    const bump = el("reps");
    bump.classList.add("bump");
    setTimeout(() => bump.classList.remove("bump"), 220);
    el("event-line").textContent = snapshot.callout;
    if (state.speakOn && snapshot.callout) {
      state.engine.api_speak(snapshot.callout);
    }
  } else if (snapshot.event === "low_confidence") {
    el("event-line").textContent = snapshot.callout;
  }
}

function drawSkeleton(flat) {
  const canvas = el("overlay");
  const stage = canvas.parentElement;
  const width = stage.clientWidth;
  const height = stage.clientHeight;
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, width, height);
  if (!flat) return;

  const toX = (x) => x * width;
  const toY = (y) => y * height;
  ctx.lineWidth = 4;
  ctx.strokeStyle = "#1f6feb";
  ctx.fillStyle = "#0b4bb3";

  BONES.forEach(([a, b]) => {
    if (!TRACKED.includes(a) || !TRACKED.includes(b)) return;
    ctx.beginPath();
    ctx.moveTo(toX(flat[a * 4]), toY(flat[a * 4 + 1]));
    ctx.lineTo(toX(flat[b * 4]), toY(flat[b * 4 + 1]));
    ctx.stroke();
  });

  TRACKED.forEach((index) => {
    const visibility = flat[index * 4 + 3];
    ctx.globalAlpha = visibility < 0.5 ? 0.25 : 1;
    ctx.beginPath();
    ctx.arc(toX(flat[index * 4]), toY(flat[index * 4 + 1]), 6, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  });
}

/* ---------- 主循环 ---------- */

async function tick() {
  if (!state.running) return;
  const engine = state.engine;
  const now = engine.api_now_ms() - state.startedAt;

  let flat = null;
  if (state.source === "synthetic") {
    flat = syntheticLandmarks(now);
  } else if (state.landmarker && el("video").readyState >= 2) {
    flat = cameraLandmarks(now);
  }

  if (flat) {
    const snapshot = JSON.parse(
      engine.api_step_json(state.motion, state.audience, flat, now),
    );
    renderState(snapshot);
    drawSkeleton(flat);
  } else {
    drawSkeleton(null);
  }

  state.rafId = requestAnimationFrame(tick);
}

async function start() {
  if (!state.engine) return;
  const translation = applyTranslation();
  if (!translation) return;
  if (state.speakOn) {
    const script = JSON.parse(state.engine.api_script_json(state.motion, state.audience, 20));
    if (script.lines && script.lines.length) state.engine.api_speak(script.lines[0]);
  }
  try {
    if (state.source === "camera") {
      await startCamera();
      el("stage-placeholder").style.display = "none";
    } else {
      stopCamera();
      el("stage-placeholder").style.display = "none";
      el("source-note").textContent = "合成姿态源：离线可跑，不需要摄像头";
    }
  } catch (error) {
    el("source-note").textContent = "摄像头或 MediaPipe 不可用，已回退到合成姿态源";
    state.source = "synthetic";
    el("source").value = "synthetic";
    console.error(error);
  }
  // 先把 warm 秒数的姿态喂进去，再让时钟从暖机结束处继续，
  // 这样骨架和数字是接着的，不会出现「数字跳回 0。」
  const warmMs = state.pendingWarmMs || 0;
  state.pendingWarmMs = 0;
  if (warmMs > 0 && state.source === "synthetic") warmUp(warmMs);

  state.startedAt = state.engine.api_now_ms() - warmMs;
  state.running = true;
  el("start").disabled = true;
  cancelAnimationFrame(state.rafId);
  state.rafId = requestAnimationFrame(tick);
}

function stop() {
  state.running = false;
  cancelAnimationFrame(state.rafId);
  el("start").disabled = false;
  if (state.engine) state.engine.api_reset();
}

/* ---------- URL 参数（便于截图、录屏与评审复现）----------
 *
 * 用法示例：
 *   web/?audience=wheelchair&auto=1
 *   web/?motion=squat&audience=elderly_knee_pain&source=synthetic&auto=1&speak=0
 *
 * 支持：motion / audience / source / auto / speak / warm
 *
 *   warm=<秒数>  在开始渲染前，先把这么多秒的合成姿态「快速喂」给引擎，
 *                让计数器直接落在某个进度上。用于录屏与截图的确定性复现，
 *                也让评审不必等 10 秒才看到数字。
 * 这样一段演示就是一个可复现的 URL，截图和录屏不必依赖手动点击。
 */

function applyQueryParams() {
  const params = new URLSearchParams(window.location.search);
  const motion = params.get("motion");
  const audience = params.get("audience");
  const source = params.get("source");
  const speak = params.get("speak");
  const warm = Number(params.get("warm") || 0);

  if (motion) state.motion = motion;
  if (audience) state.audience = audience;
  if (source === "synthetic" || source === "camera") state.source = source;
  if (speak === "0") state.speakOn = false;
  if (speak === "1") state.speakOn = true;

  el("motion").value = state.motion;
  el("audience").value = state.audience;
  el("source").value = state.source;
  el("speak-toggle").textContent = `语音播报：${state.speakOn ? "开" : "关"}`;

  return {
    auto: params.get("auto") === "1",
    warmMs: Number.isFinite(warm) && warm > 0 ? Math.round(warm * 1000) : 0,
  };
}

/**
 * 把 warmMs 毫秒的合成姿态一次性喂给引擎。
 *
 * 用的是和命令行自检、自动化测试完全相同的那条链路（api_synth_landmarks →
 * api_step_json），所以这里跑出来的数字和 `moon run cmd/main` 打印的是同一套结果。
 */
function warmUp(warmMs) {
  const step = 33;
  for (let t = 0; t <= warmMs; t += step) {
    const flat = state.engine.api_synth_landmarks(state.motion, state.audience, t);
    state.engine.api_step_json(state.motion, state.audience, flat, t);
  }
}

/* ---------- 事件绑定 ---------- */

window.addEventListener("DOMContentLoaded", async () => {
  await loadEngine();
  fillSelects();
  const query = applyQueryParams();
  applyTranslation();

  el("motion").addEventListener("change", (event) => {
    state.motion = event.target.value;
    applyTranslation();
  });
  el("audience").addEventListener("change", (event) => {
    state.audience = event.target.value;
    applyTranslation();
  });
  el("source").addEventListener("change", (event) => {
    state.source = event.target.value;
    if (state.running) {
      stop();
      start();
    }
  });
  el("start").addEventListener("click", start);
  el("stop").addEventListener("click", stop);
  el("speak-toggle").addEventListener("click", (event) => {
    state.speakOn = !state.speakOn;
    event.target.textContent = `语音播报：${state.speakOn ? "开" : "关"}`;
  });
  window.addEventListener("resize", () => drawSkeleton(null));

  // 让页面在被截图前先稳定渲染一帧骨架与数字
  requestAnimationFrame(() => requestAnimationFrame(() => drawSkeleton(null)));

  if (query.auto) {
    state.pendingWarmMs = query.warmMs;
    // 自动演示：等一帧确保布局完成，再开始跑
    setTimeout(() => start(), 120);
  }
});
