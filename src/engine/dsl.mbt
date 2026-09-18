// MoveMentor 核心引擎 · 动作 DSL 解析器
//
// 动作不是写死在代码里的常量，而是一门很小的声明式语言。这样做有三点好处：
//   1. 新增一个动作 / 一个人群 = 改数据，不改引擎；
//   2. 解析结果是一个纯数据结构，能被单元测试逐字段断言；
//   3. 「翻译」这件事被逼成了显式的规则表，而不是一段提示词。
//
// 语法（行式，`#` 起注释，空行忽略）：
//
//   motion <id>                                  动作声明
//     name <自由文本>                             显示名
//     view <front|side>                          机位假设
//     tag <词>                                   可重复
//     load <轴>=<none|low|medium|high>           载荷轴：impact / knee / hip / shoulder / balance / spine
//     phase <相id> [<指标><>=|<=><数>]... [hold=<毫秒>]
//     cycle <相id>...                            重复一次的相位序列，缺省为按声明顺序
//     cue <自由文本>                             语音/文字提示，可重复
//     min_rep_ms <整数>                          两次计次之间的最小间隔（防抖）
//     hysteresis <数>                            相位滞回宽度（防抖）
//     hold_only_ms <整数>                        等长动作的总时长；>0 时该动作只计时不计次
//
//   audience <id>                                人群声明
//     name <自由文本>
//     limit <指标><>=|<=><数>                    能力边界，可重复
//     allow <轴>=<none|low|medium|high>          可承受的载荷上限，未声明的轴不做校验
//     note <自由文本>
//
//   variant <源动作id> <人群id> -> <变式动作id>   翻译规则
//     reason <自由文本>                          为什么这么翻译（会展示给用户）

///|
/// 载荷等级。把「跳跃冲击」「膝负荷」这类定性描述变成可比较的序数，
/// 让「人群能承受什么」和「动作要求什么」能用同一把尺子对齐。
pub(all) enum Level {
  NoLoad
  Low
  Medium
  High
} derive(Debug, Eq)

///|
pub fn Level::rank(self : Level) -> Int {
  match self {
    NoLoad => 0
    Low => 1
    Medium => 2
    High => 3
  }
}

///|
pub fn Level::token(self : Level) -> String {
  match self {
    NoLoad => "none"
    Low => "low"
    Medium => "medium"
    High => "high"
  }
}

///|
pub fn Level::label(self : Level) -> String {
  match self {
    NoLoad => "无"
    Low => "低"
    Medium => "中"
    High => "高"
  }
}

///|
pub fn Level::from_token(token : String) -> Level? {
  if token == "none" {
    Some(NoLoad)
  } else if token == "low" {
    Some(Low)
  } else if token == "medium" {
    Some(Medium)
  } else if token == "high" {
    Some(High)
  } else {
    None
  }
}

///|
/// 约束的比较方向。
pub(all) enum Compare {
  AtLeast
  AtMost
} derive(Debug, Eq)

///|
pub fn Compare::token(self : Compare) -> String {
  match self {
    AtLeast => ">="
    AtMost => "<="
  }
}

///|
/// 一条指标约束：`metric >= value` 或 `metric <= value`。
///
/// 「相位目标」与「人群能力边界」用的是同一个类型——正因为同构，
/// 才可能用一套纯函数判断某个人群能不能做某个动作。
pub(all) struct Constraint {
  metric : String
  cmp : Compare
  value : Double
} derive(Debug)

///|
pub fn Constraint::new(
  metric : String,
  cmp : Compare,
  value : Double,
) -> Constraint {
  { metric, cmp, value, }
}

///|
/// 严格满足。
pub fn Constraint::satisfied_by(self : Constraint, observed : Double) -> Bool {
  match self.cmp {
    AtLeast => observed >= self.value
    AtMost => observed <= self.value
  }
}

///|
/// 放宽 `hysteresis` 后的满足条件：进入相位用严格阈值，维持相位用放宽阈值。
/// 这是计数状态机抖动抑制的一半（另一半是 `min_rep_ms`）。
pub fn Constraint::satisfied_with_hysteresis(
  self : Constraint,
  observed : Double,
  hysteresis : Double,
) -> Bool {
  let margin = hysteresis.abs()
  match self.cmp {
    AtLeast => observed >= self.value - margin
    AtMost => observed <= self.value + margin
  }
}

///|
pub fn Constraint::to_text(self : Constraint) -> String {
  "\{self.metric}\{self.cmp.token()}\{self.value}"
}

///|
/// 一个相位：一组必须同时满足的指标约束，以及需要保持的时长。
pub(all) struct PhaseSpec {
  id : String
  targets : Array[Constraint]
  hold_ms : Int
} derive(Debug)

///|
/// 一个动作的完整定义。
pub(all) struct MotionSpec {
  id : String
  display_name : String
  view : String
  tags : Array[String]
  loads : Array[(String, Level)]
  phases : Array[PhaseSpec]
  cycle : Array[String]
  cues : Array[String]
  min_rep_ms : Int
  hysteresis : Double
  hold_only_ms : Int
} derive(Debug)

///|
/// 该动作是否是等长保持类（只计时不计次）。
pub fn MotionSpec::is_hold_only(self : MotionSpec) -> Bool {
  self.hold_only_ms > 0
}

///|
/// 按 id 找相位。
pub fn MotionSpec::phase(self : MotionSpec, id : String) -> PhaseSpec? {
  for p in self.phases {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

///|
/// 重复动作时的相位顺序。`cycle` 为空时退化为按声明顺序。
pub fn MotionSpec::cycle_phases(self : MotionSpec) -> Array[PhaseSpec] {
  let out : Array[PhaseSpec] = []
  let order = if self.cycle.is_empty() {
    let ids : Array[String] = []
    for p in self.phases {
      ids.push(p.id)
    }
    ids
  } else {
    self.cycle
  }
  for id in order {
    match self.phase(id) {
      Some(p) => out.push(p)
      None => ()
    }
  }
  out
}

///|
/// 该动作要求的所有指标名（去重后按出现顺序）。
pub fn MotionSpec::required_metrics(self : MotionSpec) -> Array[String] {
  let out : Array[String] = []
  for p in self.phases {
    for t in p.targets {
      let mut seen = false
      for name in out {
        if name == t.metric {
          seen = true
        }
      }
      if !seen {
        out.push(t.metric)
      }
    }
  }
  out
}

///|
/// 一个人群的能力画像。
pub(all) struct AudienceProfile {
  id : String
  display_name : String
  limits : Array[Constraint]
  allowances : Array[(String, Level)]
  notes : Array[String]
} derive(Debug)

///|
/// 该人群对某个载荷轴的上限；未声明则返回 `None`（表示不做校验）。
pub fn AudienceProfile::allowance(
  self : AudienceProfile,
  axis : String,
) -> Level? {
  for (a, level) in self.allowances {
    if a == axis {
      return Some(level)
    }
  }
  None
}

///|
/// 该人群对某个指标是否声明了边界。可能有多条，取最严格的那条用于比较。
pub fn AudienceProfile::metric_limits(
  self : AudienceProfile,
  metric : String,
) -> Array[Constraint] {
  let out : Array[Constraint] = []
  for c in self.limits {
    if c.metric == metric {
      out.push(c)
    }
  }
  out
}

///|
/// 该人群是否声明了任何限制。没有限制 = 基线人群，翻译时是恒等映射。
pub fn AudienceProfile::is_unrestricted(self : AudienceProfile) -> Bool {
  self.limits.is_empty() && self.allowances.is_empty()
}

///|
/// 一条翻译规则：`源动作 + 人群 -> 变式动作`。
pub(all) struct VariantRule {
  source : String
  audience : String
  target : String
  reason : String
} derive(Debug)

///|
/// 解析诊断。收集而不是快速失败：作者一次就能看到全部问题。
pub(all) struct DslIssue {
  line : Int
  message : String
  source_line : String
} derive(Debug)

///|
/// 一份完整的规则表。
pub(all) struct DslProgram {
  motions : Array[MotionSpec]
  audiences : Array[AudienceProfile]
  variants : Array[VariantRule]
  issues : Array[DslIssue]
} derive(Debug)

///|
pub fn DslProgram::motion(self : DslProgram, id : String) -> MotionSpec? {
  for m in self.motions {
    if m.id == id {
      return Some(m)
    }
  }
  None
}

///|
pub fn DslProgram::audience(self : DslProgram, id : String) -> AudienceProfile? {
  for a in self.audiences {
    if a.id == id {
      return Some(a)
    }
  }
  None
}

///|
/// 命中 `源动作 + 人群` 的翻译规则。
pub fn DslProgram::variant_for(
  self : DslProgram,
  source : String,
  audience : String,
) -> VariantRule? {
  for v in self.variants {
    if v.source == source && v.audience == audience {
      return Some(v)
    }
  }
  None
}

///|
/// 反向翻译：哪些动作会因为该人群被翻译成这个变式。
/// 「坐姿抬腿」在这里会同时命中「开合跳」和「深蹲」。
pub fn DslProgram::sources_of(
  self : DslProgram,
  target : String,
) -> Array[String] {
  let out : Array[String] = []
  for v in self.variants {
    if v.target == target {
      let mut seen = false
      for s in out {
        if s == v.source {
          seen = true
        }
      }
      if !seen {
        out.push(v.source)
      }
    }
  }
  out
}

///|
/// 该人群下所有有变式的动作 id。
pub fn DslProgram::covered_motions(
  self : DslProgram,
  audience : String,
) -> Array[String] {
  let out : Array[String] = []
  for v in self.variants {
    if v.audience == audience {
      out.push(v.source)
    }
  }
  out
}

///|
/// 一个待解析的声明块。
priv struct DslBlock {
  kind : String
  header : String
  first_line : Int
  body : Array[(Int, String)]
}

///|
/// 把 `key rest` 形式的行拆成两段（key 取第一个空格之前的部分）。
fn split_head(line : StringView) -> (String, String) {
  match line.split_once(" ") {
    Some((k, v)) => (k.to_owned(), v.trim().to_owned())
    None => (line.to_owned(), "")
  }
}

///|
/// 按空格切分，忽略连续空格产生的空串。
fn tokens_of(text : StringView) -> Array[String] {
  let out : Array[String] = []
  for piece in text.split(" ") {
    if !piece.is_empty() {
      out.push(piece.to_owned())
    }
  }
  out
}

///|
/// 解析十进制浮点数。刻意不用 `parse_double`：本引擎里所有数值都必须在
/// 测试里可预期地复现，这里只接受 `[+-]?\d+(\.\d+)?`，其余一律判为非法。
pub fn parse_double_opt(text : String) -> Double? {
  if text.is_empty() {
    return None
  }
  let mut index = 0
  let mut sign = 1.0
  let mut int_part = 0.0
  let mut frac_part = 0.0
  let mut frac_scale = 1.0
  let mut in_fraction = false
  let mut seen_digit = false
  let mut ok = true
  while index < text.length() {
    let c = text.get_char(index).unwrap()
    if index == 0 && (c == '-' || c == '+') {
      if c == '-' {
        sign = -1.0
      }
    } else if c == '.' {
      if in_fraction {
        ok = false
      } else {
        in_fraction = true
      }
    } else if c >= '0' && c <= '9' {
      seen_digit = true
      let digit = (c.to_int() - 48).to_double()
      if in_fraction {
        frac_scale = frac_scale * 10.0
        frac_part = frac_part + digit / frac_scale
      } else {
        int_part = int_part * 10.0 + digit
      }
    } else {
      ok = false
    }
    index = index + 1
  }
  if ok && seen_digit {
    Some(sign * (int_part + frac_part))
  } else {
    None
  }
}

///|
/// 解析 `<指标>>=<数>` 或 `<指标><=<数>`。
pub fn parse_constraint(text : String) -> Constraint? {
  match text.split_once(">=") {
    Some((metric, value)) => make_constraint(metric, AtLeast, value)
    None =>
      match text.split_once("<=") {
        Some((metric, value)) => make_constraint(metric, AtMost, value)
        None => None
      }
  }
}

///|
fn make_constraint(
  metric_view : StringView,
  cmp : Compare,
  value_view : StringView,
) -> Constraint? {
  let metric = metric_view.trim().to_owned()
  if metric.is_empty() {
    return None
  }
  match parse_double_opt(value_view.trim().to_owned()) {
    Some(value) => Some(Constraint::new(metric, cmp, value))
    None => None
  }
}

///|
fn issue(line : Int, message : String, source_line : String) -> DslIssue {
  { line, message, source_line, }
}

///|
fn split_blocks(source : String) -> (Array[DslBlock], Array[DslIssue]) {
  let blocks : Array[DslBlock] = []
  let issues : Array[DslIssue] = []
  let mut kind = ""
  let mut header = ""
  let mut first_line = 0
  let mut body : Array[(Int, String)] = []
  let mut line_no = 0
  for raw in source.split("\n") {
    line_no = line_no + 1
    let line = raw.trim()
    let blank_or_comment = line.is_empty() || line.has_prefix("#")
    if !blank_or_comment {
      let (key, rest) = split_head(line)
      let is_decl = key == "motion" || key == "audience" || key == "variant"
      if is_decl {
        if kind != "" {
          blocks.push({ kind, header, first_line, body, })
        }
        kind = key
        header = rest
        first_line = line_no
        body = []
        if header.is_empty() {
          issues.push(
            issue(line_no, "\{key} 声明缺少标识符", line.to_owned()),
          )
        }
      } else if kind == "" {
        issues.push(
          issue(
            line_no,
            "缺少 motion / audience / variant 声明头",
            line.to_owned(),
          ),
        )
      } else {
        body.push((line_no, line.to_owned()))
      }
    }
  }
  if kind != "" {
    blocks.push({ kind, header, first_line, body, })
  }
  (blocks, issues)
}

///|
/// 解析 `phase <id> [指标约束]... [hold=<毫秒>]`。
fn build_phase(
  text : String,
  line_no : Int,
  issues : Array[DslIssue],
) -> PhaseSpec? {
  let parts = tokens_of(text)
  if parts.length() == 0 {
    issues.push(issue(line_no, "phase 缺少相位标识符", text))
    return None
  }
  let id = parts[0]
  let targets : Array[Constraint] = []
  let mut hold_ms = 0
  for i in 1..<parts.length() {
    let token = parts[i]
    if token.has_prefix("hold=") {
      match parse_double_opt(token[5:].trim().to_owned()) {
        Some(value) if value >= 0.0 => hold_ms = value.to_int()
        _ =>
          issues.push(
            issue(line_no, "hold= 需要一个非负数：\{token}", text),
          )
      }
    } else {
      match parse_constraint(token) {
        Some(c) =>
          if is_known_metric(c.metric) {
            targets.push(c)
          } else {
            issues.push(
              issue(
                line_no,
                "未知指标 `\{c.metric}`（见 engine/metrics.mbt）",
                text,
              ),
            )
          }
        None =>
          issues.push(
            issue(line_no, "无法解析的相位条件：\{token}", text),
          )
      }
    }
  }
  Some({ id, targets, hold_ms, })
}

///|
fn build_motion(block : DslBlock) -> (MotionSpec?, Array[DslIssue]) {
  let issues : Array[DslIssue] = []
  let mut display_name = ""
  let mut view = "front"
  let tags : Array[String] = []
  let loads : Array[(String, Level)] = []
  let phases : Array[PhaseSpec] = []
  let cycle : Array[String] = []
  let cues : Array[String] = []
  let mut min_rep_ms = 0
  let mut hysteresis = 0.0
  let mut hold_only_ms = 0
  for (line_no, text) in block.body {
    let (key, rest) = split_head(text)
    if key == "name" {
      display_name = rest
    } else if key == "view" {
      if rest == "front" || rest == "side" {
        view = rest
      } else {
        issues.push(
          issue(line_no, "view 只支持 front 或 side：\{rest}", text),
        )
      }
    } else if key == "tag" {
      if rest.is_empty() {
        issues.push(issue(line_no, "tag 需要一个词", text))
      } else {
        tags.push(rest)
      }
    } else if key == "load" {
      match rest.split_once("=") {
        Some((axis, level_token)) =>
          match Level::from_token(level_token.trim().to_owned()) {
            Some(level) => loads.push((axis.trim().to_owned(), level))
            None =>
              issues.push(
                issue(
                  line_no,
                  "载荷等级只支持 none/low/medium/high：\{rest}",
                  text,
                ),
              )
          }
        None =>
          issues.push(issue(line_no, "load 需要写成 <轴>=<等级>", text))
      }
    } else if key == "phase" {
      match build_phase(rest, line_no, issues) {
        Some(p) => phases.push(p)
        None => ()
      }
    } else if key == "cycle" {
      for id in tokens_of(rest) {
        cycle.push(id)
      }
    } else if key == "cue" {
      if rest.is_empty() {
        issues.push(issue(line_no, "cue 需要内容", text))
      } else {
        cues.push(rest)
      }
    } else if key == "min_rep_ms" {
      match parse_double_opt(rest) {
        Some(value) if value >= 0.0 => min_rep_ms = value.to_int()
        _ =>
          issues.push(issue(line_no, "min_rep_ms 需要一个非负数", text))
      }
    } else if key == "hysteresis" {
      match parse_double_opt(rest) {
        Some(value) if value >= 0.0 => hysteresis = value
        _ =>
          issues.push(issue(line_no, "hysteresis 需要一个非负数", text))
      }
    } else if key == "hold_only_ms" {
      match parse_double_opt(rest) {
        Some(value) if value > 0.0 => hold_only_ms = value.to_int()
        _ =>
          issues.push(issue(line_no, "hold_only_ms 需要一个正数", text))
      }
    } else {
      issues.push(
        issue(line_no, "动作声明里不认识的字段 `\{key}`", text),
      )
    }
  }
  if block.header.is_empty() {
    return (None, issues)
  }
  if display_name.is_empty() {
    issues.push(
      issue(block.first_line, "动作缺少 name", "motion \{block.header}"),
    )
  }
  if phases.length() == 0 && hold_only_ms == 0 {
    issues.push(
      issue(
        block.first_line,
        "动作既没有 phase 也没有 hold_only_ms",
        "motion \{block.header}",
      ),
    )
  }
  for id in cycle {
    let mut found = false
    for p in phases {
      if p.id == id {
        found = true
      }
    }
    if !found {
      issues.push(
        issue(
          block.first_line,
          "cycle 引用了不存在的相位 `\{id}`",
          "motion \{block.header}",
        ),
      )
    }
  }
  let spec : MotionSpec = {
    id: block.header,
    display_name,
    view,
    tags,
    loads,
    phases,
    cycle,
    cues,
    min_rep_ms,
    hysteresis,
    hold_only_ms,
  }
  (Some(spec), issues)
}

///|
fn build_audience(block : DslBlock) -> (AudienceProfile?, Array[DslIssue]) {
  let issues : Array[DslIssue] = []
  let mut display_name = ""
  let limits : Array[Constraint] = []
  let allowances : Array[(String, Level)] = []
  let notes : Array[String] = []
  for (line_no, text) in block.body {
    let (key, rest) = split_head(text)
    if key == "name" {
      display_name = rest
    } else if key == "limit" {
      match parse_constraint(rest) {
        Some(c) =>
          if is_known_metric(c.metric) {
            limits.push(c)
          } else {
            issues.push(
              issue(
                line_no,
                "未知指标 `\{c.metric}`（见 engine/metrics.mbt）",
                text,
              ),
            )
          }
        None =>
          issues.push(
            issue(line_no, "无法解析的能力边界：\{rest}", text),
          )
      }
    } else if key == "allow" {
      match rest.split_once("=") {
        Some((axis, level_token)) =>
          match Level::from_token(level_token.trim().to_owned()) {
            Some(level) => allowances.push((axis.trim().to_owned(), level))
            None =>
              issues.push(
                issue(
                  line_no,
                  "载荷等级只支持 none/low/medium/high：\{rest}",
                  text,
                ),
              )
          }
        None =>
          issues.push(issue(line_no, "allow 需要写成 <轴>=<等级>", text))
      }
    } else if key == "note" {
      if !rest.is_empty() {
        notes.push(rest)
      }
    } else {
      issues.push(
        issue(line_no, "人群声明里不认识的字段 `\{key}`", text),
      )
    }
  }
  if block.header.is_empty() {
    return (None, issues)
  }
  if display_name.is_empty() {
    issues.push(
      issue(block.first_line, "人群缺少 name", "audience \{block.header}"),
    )
  }
  let profile : AudienceProfile = {
    id: block.header,
    display_name,
    limits,
    allowances,
    notes,
  }
  (Some(profile), issues)
}

///|
fn build_variant(block : DslBlock) -> (VariantRule?, Array[DslIssue]) {
  let issues : Array[DslIssue] = []
  let mut reason = ""
  for (line_no, text) in block.body {
    let (key, rest) = split_head(text)
    if key == "reason" {
      reason = rest
    } else {
      issues.push(
        issue(line_no, "variant 声明里不认识的字段 `\{key}`", text),
      )
    }
  }
  match block.header.split_once("->") {
    Some((left, right)) => {
      let source_tokens = tokens_of(left)
      let target_tokens = tokens_of(right)
      if source_tokens.length() != 2 || target_tokens.length() != 1 {
        issues.push(
          issue(
            block.first_line,
            "variant 需要写成 <源动作> <人群> -> <变式动作>",
            block.header,
          ),
        )
        (None, issues)
      } else {
        let rule : VariantRule = {
          source: source_tokens[0],
          audience: source_tokens[1],
          target: target_tokens[0],
          reason,
        }
        (Some(rule), issues)
      }
    }
    None => {
      issues.push(issue(block.first_line, "variant 缺少 `->`", block.header))
      (None, issues)
    }
  }
}

///|
/// 解析整份规则表。
///
/// 解析期的错误全部进入 `program.issues`，同时会把语义问题一并报出来：
/// 重名、variant 指向不存在的动作/人群、把变式再接一层翻译（避免翻译链）。
pub fn parse_program(source : String) -> DslProgram {
  let (blocks, block_issues) = split_blocks(source)
  let motions : Array[MotionSpec] = []
  let audiences : Array[AudienceProfile] = []
  let variants : Array[VariantRule] = []
  let issues : Array[DslIssue] = []
  for i in 0..<block_issues.length() {
    issues.push(block_issues[i])
  }
  for block in blocks {
    if block.kind == "motion" {
      let (spec, found) = build_motion(block)
      for i in 0..<found.length() {
        issues.push(found[i])
      }
      match spec {
        Some(s) =>
          if has_motion(motions, s.id) {
            issues.push(
              issue(
                block.first_line,
                "动作 id 重复：\{s.id}",
                "motion \{s.id}",
              ),
            )
          } else {
            motions.push(s)
          }
        None => ()
      }
    } else if block.kind == "audience" {
      let (profile, found) = build_audience(block)
      for i in 0..<found.length() {
        issues.push(found[i])
      }
      match profile {
        Some(p) =>
          if has_audience(audiences, p.id) {
            issues.push(
              issue(
                block.first_line,
                "人群 id 重复：\{p.id}",
                "audience \{p.id}",
              ),
            )
          } else {
            audiences.push(p)
          }
        None => ()
      }
    } else if block.kind == "variant" {
      let (rule, found) = build_variant(block)
      for i in 0..<found.length() {
        issues.push(found[i])
      }
      match rule {
        Some(r) => variants.push(r)
        None => ()
      }
    }
  }
  let program : DslProgram = { motions, audiences, variants, issues, }
  check_cross_references(program)
  program
}

///|
fn has_motion(motions : Array[MotionSpec], id : String) -> Bool {
  for m in motions {
    if m.id == id {
      return true
    }
  }
  false
}

///|
fn has_audience(audiences : Array[AudienceProfile], id : String) -> Bool {
  for a in audiences {
    if a.id == id {
      return true
    }
  }
  false
}

///|
/// 跨声明一致性检查。翻译规则指向不存在的东西，比解析错误更危险：
/// 它会在演示当天才暴露，所以必须在解析期就拦下来。
fn check_cross_references(program : DslProgram) -> Unit {
  for rule in program.variants {
    if !has_motion(program.motions, rule.source) {
      program.issues.push(
        issue(
          0,
          "翻译规则引用了不存在的源动作 `\{rule.source}`",
          rule.source,
        ),
      )
    }
    if !has_motion(program.motions, rule.target) {
      program.issues.push(
        issue(
          0,
          "翻译规则引用了不存在的变式动作 `\{rule.target}`",
          rule.target,
        ),
      )
    }
    if !has_audience(program.audiences, rule.audience) {
      program.issues.push(
        issue(
          0,
          "翻译规则引用了不存在的人群 `\{rule.audience}`",
          rule.audience,
        ),
      )
    }
    if rule.source == rule.target {
      program.issues.push(
        issue(
          0,
          "翻译规则把动作映射到了它自己：\{rule.source}",
          rule.source,
        ),
      )
    }
  }
  for rule in program.variants {
    for other in program.variants {
      if other.source == rule.target {
        program.issues.push(
          issue(
            0,
            "翻译链不被支持：`\{rule.target}` 既是变式又是源动作（\{other.source} -> \{other.target}）",
            rule.target,
          ),
        )
      }
    }
  }
}
