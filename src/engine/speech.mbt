// MoveMentor 核心引擎 · 指导语生成
//
// 模板优先，确定性优先。
//
// 为什么不用大模型写这几句话？因为「什么时候说哪一句」是产品逻辑的一部分，
// 必须能被测试、能在离线演示里稳定复现。模板能覆盖的部分就交给模板；
// 真要润色文案，那是模板外面的可选一层，不该混进引擎。
//
// 另一个刻意的选择：措辞统一为「低冲击替代方案」「降低关节负荷」，
// 绝不说「安全」「适合病人」「医疗有效」。这是健康类应用的红线。

///|
/// 固定的边界声明，任何脚本的最后一句都是它。
pub fn safety_line() -> String {
  "如果感到疼痛、头晕或任何不适，请立即停止。本工具给出的是降低关节负荷的变式，不构成医疗建议，具体请遵医嘱。"
}

///|
/// 开场：告诉用户「你现在看到的是哪个版本」。
pub fn opening_line(translation : Translation) -> String {
  "\{translation.audience_name}版本，动作是\{translation.plan.display_name}。"
}

///|
/// 当结果不是原动作时，说明它是从哪来的。
pub fn translation_notice(translation : Translation) -> String {
  if translation.kind == "identity" {
    "该人群没有额外限制，保持原动作。"
  } else if translation.kind == "substituted" {
    "原动作是\{translation.requested_name}，这里给出的是同族的替代动作。"
  } else {
    "这是\{translation.requested_name}的低冲击替代方案。"
  }
}

///|
/// 完整的一段指导语，按顺序播报。
pub fn guidance_script(
  translation : Translation,
  duration_s : Int,
  rounds : Int,
) -> Array[String] {
  let plan = translation.plan
  let script : Array[String] = []
  script.push(opening_line(translation))
  script.push(translation_notice(translation))
  for cue in plan.cues {
    script.push(cue)
  }
  if plan.is_hold_only() {
    script.push(
      "保持 \{plan.hold_only_ms / 1000} 秒，中间可以随时停下休息。",
    )
  } else {
    script.push("跟着节奏做 \{rounds} 次，大约 \{duration_s} 秒。")
  }
  script.push(safety_line())
  script
}

///|
/// 计次播报。
pub fn rep_callout(reps : Int) -> String {
  "\{reps}"
}

///|
/// 等长保持的秒数播报。
pub fn hold_callout(seconds : Int) -> String {
  "保持 \{seconds} 秒"
}

///|
/// 一次翻译为什么成立——给评委和用户看的理由。
pub fn rationale_lines(translation : Translation) -> Array[String] {
  let lines : Array[String] = []
  lines.push(translation.reason)
  for check in translation.checks {
    lines.push(check)
  }
  lines
}
