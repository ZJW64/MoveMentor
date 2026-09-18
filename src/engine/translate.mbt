// MoveMentor 核心引擎 · 安全翻译引擎
//
// 这一层的职责只有一句话：
//   给定「一个动作 + 一个人群」，输出该人群可以做的版本，并给出为什么。
//
// 它是确定性的：
//   - 查表（variant 规则）决定用哪个变式；
//   - 校验（validate）用同一套约束类型比较「动作要求」与「人群边界」；
//   - 没有任何一次网络请求、没有模型采样、没有「提示词」。
// 因此它可以被穷举测试：内置规则表里的每一条映射都必须通过校验，
// 这条断言（见 translate_wbtest.mbt）就是这张规则表的回归保护网。

///|
/// 一次翻译的完整结果。
///
/// `kind` 取 `identity` / `translated` / `substituted`，用字符串而不是枚举，
/// 是因为它要直接进入界面与 JSON 输出，字符串的调试成本最低。
pub(all) struct Translation {
  requested_id : String
  requested_name : String
  audience_id : String
  audience_name : String
  plan : MotionSpec
  kind : String
  reason : String
  checks : Array[String]
} derive(Debug)

///|
/// 翻译入口的三种结果。
///
/// `Unsupported` 不是错误处理，而是一种**明确的拒绝**：
/// 规则表里没有这条映射、也没有可替代的同族动作时，引擎宁可不给方案，
/// 也不猜。这在面向老年人/慢病人群的场景里是必须的取舍。
pub(all) enum TranslationOutcome {
  Translated(Translation)
  Substituted(Translation)
  Unsupported(String)
} derive(Debug)

///|
/// 判断一个动作是否落在某个人群的能力范围内。
///
/// 返回空数组 = 通过。每条违规都是一句可以直接展示给人看的中文说明。
pub fn validate(plan : MotionSpec, audience : AudienceProfile) -> Array[String] {
  let violations : Array[String] = []
  for phase in plan.phases {
    for target in phase.targets {
      for limit in audience.metric_limits(target.metric) {
        if conflicts(target, limit) {
          violations.push(
            "相位 `\{phase.id}` 要求 \{target.to_text()}，超出该人群边界 \{limit.to_text()}",
          )
        }
      }
    }
  }
  for (axis, level) in plan.loads {
    match audience.allowance(axis) {
      Some(allowed) =>
        if level.rank() > allowed.rank() {
          violations.push(
            "\{axis} 载荷为「\{level.label()}」，超出该人群可承受的「\{allowed.label()}」",
          )
        }
      None => ()
    }
  }
  violations
}

///|
/// 两条约束是否互相冲突。
///
/// 只有「动作要求往上 ≥ X」而「人群上限说 ≤ Y 且 X > Y」，
/// 或「动作要求往下 ≤ X」而「人群下限说 ≥ Y 且 X < Y」才算冲突。
/// 同向的两条约束永远不冲突——这是这套规则能保持简单的原因。
pub fn conflicts(target : Constraint, limit : Constraint) -> Bool {
  match (target.cmp, limit.cmp) {
    (AtLeast, AtMost) => target.value > limit.value
    (AtMost, AtLeast) => target.value < limit.value
    _ => false
  }
}

///|
/// 翻译主入口。
pub fn translate(
  program : DslProgram,
  motion_id : String,
  audience_id : String,
) -> TranslationOutcome {
  let motion = match program.motion(motion_id) {
    Some(m) => m
    None => return Unsupported("规则表里没有动作 `\{motion_id}`")
  }
  let audience = match program.audience(audience_id) {
    Some(a) => a
    None => return Unsupported("规则表里没有人群 `\{audience_id}`")
  }
  if audience.is_unrestricted() {
    return Translated({
      requested_id: motion.id,
      requested_name: motion.display_name,
      audience_id: audience.id,
      audience_name: audience.display_name,
      plan: motion,
      kind: "identity",
      reason: "该人群没有声明额外限制，动作保持原样。",
      checks: [
        "人群未声明任何载荷上限与指标边界，无需降级",
        "动作保持原样：\{motion.display_name}",
      ],
    })
  }
  match program.variant_for(motion_id, audience_id) {
    Some(rule) =>
      match program.motion(rule.target) {
        Some(target_plan) => {
          let violations = validate(target_plan, audience)
          if violations.length() > 0 {
            Unsupported(
              "规则表不自洽：`\{rule.target}` 仍然超出「\{audience.display_name}」的能力边界。\{violations[0]}",
            )
          } else {
            Translated({
              requested_id: motion.id,
              requested_name: motion.display_name,
              audience_id: audience.id,
              audience_name: audience.display_name,
              plan: target_plan,
              kind: "translated",
              reason: rule.reason,
              checks: build_checks(target_plan, audience, Some(motion)),
            })
          }
        }
        None =>
          Unsupported(
            "规则表把 `\{motion_id}` 指向了不存在的变式 `\{rule.target}`",
          )
      }
    None =>
      match find_substitute(program, motion, audience) {
        Some(candidate) =>
          Substituted({
            requested_id: motion.id,
            requested_name: motion.display_name,
            audience_id: audience.id,
            audience_name: audience.display_name,
            plan: candidate,
            kind: "substituted",
            reason: "规则表里还没有「\{motion.display_name}」在这个人群下的专属变式，已替换为同族的「\{candidate.display_name}」。",
            checks: build_checks(candidate, audience, Some(motion)),
          })
        None =>
          Unsupported(
            "「\{motion.display_name}」在「\{audience.display_name}」下暂无可用方案，建议咨询专业人士。",
          )
      }
  }
}

///|
/// 在没有专属变式时，找一个能过校验的同族动作。
///
/// 「同族」= 至少共享一个 tag。取共享 tag 最多的那个；并列时取声明在前的那个，
/// 保证同一个输入永远得到同一个输出。
pub fn find_substitute(
  program : DslProgram,
  motion : MotionSpec,
  audience : AudienceProfile,
) -> MotionSpec? {
  let mut best : MotionSpec? = None
  let mut best_score = 0
  for candidate in program.motions {
    if candidate.id != motion.id {
      let score = shared_tags(motion, candidate)
      if score > 0 &&
        validate(candidate, audience).length() == 0 &&
        best_score < score {
        best = Some(candidate)
        best_score = score
      }
    }
  }
  best
}

///|
pub fn shared_tags(a : MotionSpec, b : MotionSpec) -> Int {
  let mut count = 0
  for tag in a.tags {
    for other in b.tags {
      if tag == other {
        count = count + 1
      }
    }
  }
  count
}

///|
/// 生成校验证据。
///
/// 这些字符串会原样出现在界面上「为什么这个版本成立」那一栏，
/// 所以它们必须是真的被比较过的量，而不是模板话术。
/// 措辞上只说「通过 / 无冲突 / 未做限制」，不说「安全」——见
/// docs/06-安全边界与免责声明.md。
pub fn build_checks(
  plan : MotionSpec,
  audience : AudienceProfile,
  source : MotionSpec?,
) -> Array[String] {
  let checks : Array[String] = []
  for (axis, level) in plan.loads {
    match audience.allowance(axis) {
      Some(allowed) =>
        checks.push(
          "载荷 \{axis}：动作「\{level.label()}」≤ 人群上限「\{allowed.label()}」",
        )
      None =>
        checks.push("载荷 \{axis}：人群未声明上限，不做限制")
    }
  }
  for limit in audience.limits {
    let mut required = false
    let mut text = ""
    for phase in plan.phases {
      for target in phase.targets {
        if target.metric == limit.metric {
          required = true
          text = target.to_text()
        }
      }
    }
    if required {
      checks.push(
        "指标 \{limit.metric}（\{metric_label(limit.metric)}）：动作要求 \{text}，人群边界 \{limit.to_text()}，无冲突",
      )
    }
  }
  match source {
    Some(origin) => {
      checks.push(
        "人群边界共 \{audience.limits.length()} 条、载荷上限 \{audience.allowances.length()} 条，本变式全部通过",
      )
      checks.push(
        "原动作：\{origin.display_name}，共 \{origin.phases.length()} 个相位",
      )
    }
    None => ()
  }
  checks
}

///|
/// 反向翻译：这个变式是哪些动作翻译过来的。
///
/// 「坐姿抬腿」会同时命中「开合跳」和「深蹲」——同一个变式服务多个原动作，
/// 这正是「一张映射表的双向查询」而不是「N 个一对一特例」的证据。
pub fn reverse_sources(
  program : DslProgram,
  variant_motion_id : String,
) -> Array[MotionSpec] {
  let out : Array[MotionSpec] = []
  for source_id in program.sources_of(variant_motion_id) {
    match program.motion(source_id) {
      Some(m) => out.push(m)
      None => ()
    }
  }
  out
}

///|
/// 一行式标题，用于界面顶部与日志。
pub fn Translation::headline(self : Translation) -> String {
  "\{self.requested_name} → \{self.plan.display_name}（\{self.audience_name}）"
}
