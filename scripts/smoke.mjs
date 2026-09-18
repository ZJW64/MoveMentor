// MoveMentor · 桥接层冒烟测试
//
// 作用：证明「MoonBit 编译出来的 ES Module 确实能被 JavaScript 直接调用」，
// 而且不需要浏览器、不需要摄像头、不需要网络。
//
// 用法（在仓库根目录）：
//   moon build --release --target js
//   node scripts/smoke.mjs
//
// 它检查四件事：
//   1. 13 个导出函数都在；
//   2. 翻译结果的结构与约束校验条目；
//   3. 12 秒合成姿态跑出来的计次是确定的（可回归）；
//   4. 不存在的组合会返回 ok:false 而不是抛异常。

import * as api from "../_build/js/release/build/src/bridge/bridge.js";

let failures = 0;

function check(label, condition, detail) {
  const mark = condition ? "✓" : "✗";
  if (!condition) {
    failures += 1;
  }
  console.log(`  ${mark} ${label}${detail === undefined ? "" : ` —— ${detail}`}`);
}

const EXPECTED_EXPORTS = [
  "api_version",
  "api_motion_ids",
  "api_audience_ids",
  "api_metric_names",
  "api_catalog_json",
  "api_translate_json",
  "api_script_json",
  "api_reverse_json",
  "api_reset",
  "api_step_json",
  "api_synth_landmarks",
  "api_speak",
  "api_now_ms",
];

console.log("== 1. 导出检查 ==");
for (const name of EXPECTED_EXPORTS) {
  check(`导出 ${name}`, typeof api[name] === "function", typeof api[name]);
}
check("版本号", api.api_version() === "movementor-engine/0.1.0", api.api_version());

console.log("\n== 2. 规则表概览 ==");
const catalog = JSON.parse(api.api_catalog_json());
check("动作 9 个", catalog.motion_ids.length === 9, catalog.motion_ids.length);
check("人群 4 类", catalog.audience_ids.length === 4, catalog.audience_ids.length);
check("翻译规则 9 条", catalog.rule_source.length === 9, catalog.rule_source.length);
check("指标 18 个", api.api_metric_names().length === 18, api.api_metric_names().length);

console.log("\n== 3. 翻译结果 ==");
api.api_reset();
const t = JSON.parse(api.api_translate_json("jumping_jack", "elderly_knee_pain"));
check("翻译成功", t.ok === true);
check("命中专属变式", t.kind === "translated", t.kind);
check(
  "目标动作是坐姿抬腿",
  t.plan_id === "seated_leg_lift",
  `${t.requested_name} → ${t.plan_name}`,
);
check("带约束校验条目", t.checks.length > 0, `${t.checks.length} 条`);
check("带指导语", t.cues.length > 0, `${t.cues.length} 句`);

console.log("\n== 4. 基线人群恒等映射 ==");
for (const id of ["jumping_jack", "squat", "plank"]) {
  const base = JSON.parse(api.api_translate_json(id, "general"));
  check(`${id} 在 general 下不变`, base.plan_id === id, base.plan_id);
}

console.log("\n== 5. 计数（12 秒合成姿态，确定性）==");
api.api_reset();
let reps = 0;
let lowConfidenceFrames = 0;
for (let ms = 0; ms <= 12000; ms += 33) {
  const landmarks = api.api_synth_landmarks("jumping_jack", "elderly_knee_pain", ms);
  if (landmarks.length !== 132) {
    check("关键点长度 132", false, landmarks.length);
    break;
  }
  const snap = JSON.parse(
    api.api_step_json("jumping_jack", "elderly_knee_pain", landmarks, ms),
  );
  if (snap.event === "rep") {
    reps = snap.reps;
  }
  if (snap.low_confidence) {
    lowConfidenceFrames += 1;
  }
}
check("12 秒完成 6 次坐姿抬腿", reps === 6, reps);
check("合成姿态不触发低置信", lowConfidenceFrames === 0, lowConfidenceFrames);

console.log("\n== 6. 反向翻译 ==");
const reverse = JSON.parse(api.api_reverse_json("seated_leg_lift"));
check(
  "坐姿抬腿可回溯到开合跳与深蹲",
  reverse.source_ids.includes("jumping_jack") && reverse.source_ids.includes("squat"),
  reverse.source_names.join("、"),
);

console.log("\n== 7. 输入校验 ==");
const bad = JSON.parse(
  api.api_translate_json("不存在的动作", "elderly_knee_pain"),
);
check("未知动作返回 ok:false", bad.ok === false, bad.error);
check("未知动作不抛异常", typeof bad.error === "string");
const shortFrame = JSON.parse(
  api.api_step_json("jumping_jack", "elderly_knee_pain", [1, 2, 3], 0),
);
check("关键点数量不合法时给出明确错误", shortFrame.ok === false, shortFrame.error);

console.log("");
if (failures === 0) {
  console.log("冒烟测试全部通过。");
} else {
  console.log(`冒烟测试有 ${failures} 项失败。`);
  process.exit(1);
}
