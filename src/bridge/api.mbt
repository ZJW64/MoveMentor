// MoveMentor 桥接层 · 页面可调用的接口
//
// 设计原则：**接口越窄越好**。
// 页面不需要知道引擎里有 MotionSpec、Phase、Constraint 这些东西；
// 它只需要三件事：
//   1. 我要做「开合跳」，给「膝痛人群」——你输出什么？（api_translate_json）
//   2. 这一帧关键点给你，数到第几次了？（api_step_json）
//   3. 没有摄像头的时候，给我一帧假的先跑起来。（api_synth_landmarks）
//
// 会话状态放在这里而不是页面里：计次状态机是引擎的一部分，
// 页面刷新一次不该把「已经做了几次」重置掉。

///|
/// 会话：`动作 id -> 计数器`。键用解析后的动作 id，
/// 这样「开合跳」与「深蹲」翻译成同一个「坐姿抬腿」时共用同一个计数器。
let session_keys : Array[String] = []

///|
let session_counters : Array[@engine.RepCounter] = []

///|
/// 规则表的缓存槽。只用长度为 0/1 的数组做容器，
/// 是为了避免引入可变全局变量——引擎里的状态都是显式传入的。
let program_holder : Array[@engine.DslProgram] = []

///|
fn cached_program() -> @engine.DslProgram {
  if program_holder.length() == 0 {
    program_holder.push(@engine.builtin_program())
  }
  program_holder[0]
}

///|
fn session_index(key : String) -> Int {
  for i in 0..<session_keys.length() {
    if session_keys[i] == key {
      return i
    }
  }
  -1
}

///|
fn ensure_session(plan : @engine.MotionSpec) -> Int {
  let existing = session_index(plan.id)
  if existing >= 0 {
    existing
  } else {
    session_keys.push(plan.id)
    session_counters.push(@engine.RepCounter::new(plan))
    session_keys.length() - 1
  }
}

///|
pub fn api_version() -> String {
  "movementor-engine/0.1.0"
}

///|
pub fn api_motion_ids() -> Array[String] {
  let ids : Array[String] = []
  for motion in cached_program().motions {
    ids.push(motion.id)
  }
  ids
}

///|
pub fn api_audience_ids() -> Array[String] {
  let ids : Array[String] = []
  for audience in cached_program().audiences {
    ids.push(audience.id)
  }
  ids
}

///|
pub fn api_metric_names() -> Array[String] {
  @engine.metric_names()
}

///|
/// 清空全部计次状态。切换动作或人群时调用。
pub fn api_reset() -> Unit {
  session_keys.clear()
  session_counters.clear()
}

///|
/// 规则表概览。并行数组，页面直接按下标 zip 即可。
pub fn api_catalog_json() -> String {
  let program = cached_program()
  let motion_ids : Array[String] = []
  let motion_names : Array[String] = []
  let motion_kinds : Array[String] = []
  let source_ids : Array[String] = []
  for motion in program.motions {
    motion_ids.push(motion.id)
    motion_names.push(motion.display_name)
    if motion.is_hold_only() {
      motion_kinds.push("hold")
    } else {
      motion_kinds.push("rep")
    }
    let mut is_variant = false
    for rule in program.variants {
      if rule.target == motion.id {
        is_variant = true
      }
    }
    if is_variant {
      source_ids.push(program.sources_of(motion.id).length().to_string())
    } else {
      source_ids.push("源动作")
    }
  }
  let audience_ids : Array[String] = []
  let audience_names : Array[String] = []
  for audience in program.audiences {
    audience_ids.push(audience.id)
    audience_names.push(audience.display_name)
  }
  let rule_source : Array[String] = []
  let rule_audience : Array[String] = []
  let rule_target : Array[String] = []
  for rule in program.variants {
    rule_source.push(rule.source)
    rule_audience.push(rule.audience)
    rule_target.push(rule.target)
  }
  let object = @engine.json_object()
  object.field_string_array("motion_ids", motion_ids)
  object.field_string_array("motion_names", motion_names)
  object.field_string_array("motion_kinds", motion_kinds)
  object.field_string_array("motion_roles", source_ids)
  object.field_string_array("audience_ids", audience_ids)
  object.field_string_array("audience_names", audience_names)
  object.field_string_array("rule_source", rule_source)
  object.field_string_array("rule_audience", rule_audience)
  object.field_string_array("rule_target", rule_target)
  object.finish()
}

///|
/// 翻译：`动作 + 人群 -> 方案`。
pub fn api_translate_json(motion_id : String, audience_id : String) -> String {
  match @engine.translate(cached_program(), motion_id, audience_id) {
    @engine.Translated(t) => translation_json(t)
    @engine.Substituted(t) => translation_json(t)
    @engine.Unsupported(message) => error_json(message)
  }
}

///|
fn translation_json(translation : @engine.Translation) -> String {
  let plan = translation.plan
  let object = @engine.json_object()
  object.field_bool("ok", true)
  object.field_string("kind", translation.kind)
  object.field_string("requested_id", translation.requested_id)
  object.field_string("requested_name", translation.requested_name)
  object.field_string("audience_id", translation.audience_id)
  object.field_string("audience_name", translation.audience_name)
  object.field_string("plan_id", plan.id)
  object.field_string("plan_name", plan.display_name)
  object.field_string("headline", translation.headline())
  object.field_string("reason", translation.reason)
  object.field_string_array("checks", translation.checks)
  object.field_string_array("cues", plan.cues)
  object.field_string_array("phase_ids", phase_ids(plan))
  object.field_string_array("metrics", plan.required_metrics())
  object.field_string_array(
    "metric_labels",
    metric_labels(plan.required_metrics()),
  )
  object.field_bool("is_hold_only", plan.is_hold_only())
  object.field_int("hold_only_ms", plan.hold_only_ms)
  object.field_int("min_rep_ms", plan.min_rep_ms)
  object.field_double("hysteresis", plan.hysteresis)
  object.finish()
}

///|
fn phase_ids(plan : @engine.MotionSpec) -> Array[String] {
  let ids : Array[String] = []
  for phase in plan.cycle_phases() {
    ids.push(phase.id)
  }
  ids
}

///|
fn metric_labels(metrics : Array[String]) -> Array[String] {
  let labels : Array[String] = []
  for metric in metrics {
    labels.push(@engine.metric_label(metric))
  }
  labels
}

///|
fn error_json(message : String) -> String {
  let object = @engine.json_object()
  object.field_bool("ok", false)
  object.field_string("error", message)
  object.finish()
}

///|
/// 指导语全文，页面按句播报。
pub fn api_script_json(
  motion_id : String,
  audience_id : String,
  duration_s : Int,
) -> String {
  match @engine.translate(cached_program(), motion_id, audience_id) {
    @engine.Translated(t) => script_json(t, duration_s)
    @engine.Substituted(t) => script_json(t, duration_s)
    @engine.Unsupported(message) => error_json(message)
  }
}

///|
fn script_json(translation : @engine.Translation, duration_s : Int) -> String {
  let object = @engine.json_object()
  object.field_bool("ok", true)
  object.field_string_array(
    "lines",
    @engine.guidance_script(translation, duration_s, 10),
  )
  object.field_string_array("rationale", @engine.rationale_lines(translation))
  object.finish()
}

///|
/// 反向翻译：这个动作是哪些动作的低冲击变式。
pub fn api_reverse_json(motion_id : String) -> String {
  let names : Array[String] = []
  let ids : Array[String] = []
  for source in @engine.reverse_sources(cached_program(), motion_id) {
    ids.push(source.id)
    names.push(source.display_name)
  }
  let object = @engine.json_object()
  object.field_string_array("source_ids", ids)
  object.field_string_array("source_names", names)
  object.finish()
}

///|
/// 吃进一帧关键点，返回计数快照。
///
/// `landmarks` 必须是 132 个数（33 点 × x/y/z/visibility），
/// 与 MediaPipe Pose 的 `landmarks` 顺序一致。
pub fn api_step_json(
  motion_id : String,
  audience_id : String,
  landmarks : Array[Double],
  now_ms : Int,
) -> String {
  let frame = match @engine.PoseFrame::from_flat(landmarks) {
    Some(f) => f
    None =>
      return error_json(
        "关键点数量不合法：期望 \{@engine.POSE_POINT_COUNT * @engine.POSE_STRIDE} 个数字，收到 \{landmarks.length()} 个",
      )
  }
  match @engine.translate(cached_program(), motion_id, audience_id) {
    @engine.Translated(t) => step_with(t.plan, frame, now_ms)
    @engine.Substituted(t) => step_with(t.plan, frame, now_ms)
    @engine.Unsupported(message) => error_json(message)
  }
}

///|
fn step_with(
  plan : @engine.MotionSpec,
  frame : @engine.PoseFrame,
  now_ms : Int,
) -> String {
  let index = ensure_session(plan)
  // MoonBit 的结构体是值语义：从数组取出、在本地推进、再写回。
  let counter = session_counters[index]
  let snapshot = counter.update(frame, now_ms)
  session_counters[index] = counter
  snapshot_json(snapshot)
}

///|
fn snapshot_json(snapshot : @engine.CounterSnapshot) -> String {
  let object = @engine.json_object()
  object.field_bool("ok", true)
  object.field_string("plan_id", snapshot.motion_id)
  object.field_string("phase_id", snapshot.phase_id)
  object.field_int("phase_index", snapshot.phase_index)
  object.field_int("reps", snapshot.reps)
  object.field_int("held_ms", snapshot.held_ms)
  object.field_double("progress", snapshot.progress)
  object.field_double("confidence", snapshot.confidence)
  object.field_bool("is_hold_only", snapshot.is_hold_only)
  object.field_bool(
    "low_confidence",
    snapshot.confidence < @engine.MIN_CONFIDENCE,
  )
  let event = event_token(snapshot.event)
  object.field_string("event", event.0)
  object.field_int("event_value", event.1)
  object.field_string("callout", callout(snapshot))
  object.finish()
}

///|
fn event_token(event : @engine.CounterEvent) -> (String, Int) {
  match event {
    @engine.Idle => ("idle", 0)
    @engine.EnteredPhase(_) => ("phase", 0)
    @engine.CompletedRep(n) => ("rep", n)
    @engine.HoldTick(second) => ("hold", second)
    @engine.LowConfidence => ("low_confidence", 0)
  }
}

///|
/// 该念什么。放在引擎侧，让「什么时候说什么」只存在一处。
fn callout(snapshot : @engine.CounterSnapshot) -> String {
  match snapshot.event {
    @engine.CompletedRep(n) => @engine.rep_callout(n)
    @engine.HoldTick(second) => @engine.hold_callout(second)
    @engine.LowConfidence => "看不到你的动作，请站到画面中间"
    _ => ""
  }
}

///|
/// 合成一帧关键点，让没有摄像头的机器也能跑完整条链路。
pub fn api_synth_landmarks(
  motion_id : String,
  audience_id : String,
  now_ms : Int,
) -> Array[Double] {
  match @engine.translate(cached_program(), motion_id, audience_id) {
    @engine.Translated(t) => @engine.synth_frame(t.plan, now_ms).points
    @engine.Substituted(t) => @engine.synth_frame(t.plan, now_ms).points
    @engine.Unsupported(_) =>
      Array::make(@engine.POSE_POINT_COUNT * @engine.POSE_STRIDE, 0.0)
  }
}

///|
/// 浏览器原生语音合成（Web Speech API）。
///
/// 用 FFI 放在这里而不是写在页面里，是因为「说什么」由引擎决定，
/// 「怎么发声」才是宿主的事——这条边界需要显式。
pub fn api_speak(text : String) -> Unit {
  speak_impl(text)
}

///|
extern "js" fn speak_impl(text : String) -> Unit =
  #| function(text) {
  #|   if (typeof window === "undefined" || !("speechSynthesis" in window)) {
  #|     return;
  #|   }
  #|   const utter = new SpeechSynthesisUtterance(text);
  #|   utter.lang = "zh-CN";
  #|   utter.rate = 0.95;
  #|   utter.pitch = 1.0;
  #|   window.speechSynthesis.cancel();
  #|   window.speechSynthesis.speak(utter);
  #| }

///|
/// 宿主的高精度时钟（毫秒，向下取整）。
pub fn api_now_ms() -> Int {
  now_ms_impl()
}

///|
extern "js" fn now_ms_impl() -> Int =
  #| function() {
  #|   if (typeof performance !== "undefined" && typeof performance.now === "function") {
  #|     return Math.floor(performance.now());
  #|   }
  #|   return Date.now() | 0;
  #| }
