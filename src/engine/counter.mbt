// MoveMentor 核心引擎 · 计次状态机
//
// 别小看「数到第几次」这件事：它是这类应用里最容易翻车的一环。
// 关键点轻微抖动、人在阈值附近来回晃、网络掉帧导致的 dt 跳变，
// 都会让朴素实现把 1 次算成 3 次或者干脆一次都不算。
//
// 这里用了三道防抖：
//   1. 相位滞回（hysteresis）：进入相位用严格阈值，维持相位用放宽阈值；
//   2. 最小重复间隔（min_rep_ms）：两次计次之间的硬性时间下限；
//   3. dt 钳位：两次 update 之间的时间差被限制在 200 ms 以内，
//      掉帧或切后台回来不会一次性灌进一大段「保持时间」。
// 另外，关键点平均可见度低于阈值时整帧作废，宁可漏计也不误计。

///|
/// 计数器产生的事件。界面据此决定要不要刷新、要不要播报。
pub(all) enum CounterEvent {
  Idle
  EnteredPhase(String)
  CompletedRep(Int)
  HoldTick(Int)
  LowConfidence
} derive(Debug, Eq)

///|
/// 计数器的一次快照。
pub(all) struct CounterSnapshot {
  motion_id : String
  phase_id : String
  phase_index : Int
  reps : Int
  dwell_ms : Int
  held_ms : Int
  progress : Double
  confidence : Double
  is_hold_only : Bool
  event : CounterEvent
} derive(Debug)

///|
/// 可见度低于该值即整帧作废。
pub const MIN_CONFIDENCE : Double = 0.5

///|
/// 单次 update 允许计入的最大时间差（毫秒）。
pub const MAX_DELTA_MS : Int = 200

///|
/// 计次状态机。每个「动作 + 人群」的组合持有一个实例。
pub(all) struct RepCounter {
  plan : MotionSpec
  mut phase_index : Int
  mut reps : Int
  mut dwell_ms : Int
  mut held_ms : Int
  mut last_ms : Int
  mut last_rep_ms : Int
  mut armed : Bool
  mut last_tick_second : Int
} derive(Debug)

///|
pub fn RepCounter::new(plan : MotionSpec) -> RepCounter {
  // last_rep_ms 初始化为 -min_rep_ms：保证第一次重复一定被计入，
  // 而不是被「最小间隔」在启动瞬间误杀。
  {
    plan,
    phase_index: 0,
    reps: 0,
    dwell_ms: 0,
    held_ms: 0,
    last_ms: -1,
    last_rep_ms: 0 - plan.min_rep_ms,
    armed: false,
    last_tick_second: 0,
  }
}

///|
/// 复位，用于「重新开始」。
pub fn RepCounter::reset(self : RepCounter) -> Unit {
  self.phase_index = 0
  self.reps = 0
  self.dwell_ms = 0
  self.held_ms = 0
  self.last_ms = -1
  self.last_rep_ms = 0 - self.plan.min_rep_ms
  self.armed = false
  self.last_tick_second = 0
}

///|
/// 吃进一帧，返回新的快照。
pub fn RepCounter::update(
  self : RepCounter,
  frame : PoseFrame,
  now_ms : Int,
) -> CounterSnapshot {
  let confidence = frame.tracked_visibility()
  let raw_delta = if self.last_ms < 0 { 0 } else { now_ms - self.last_ms }
  let delta = if raw_delta < 0 {
    0
  } else if raw_delta > MAX_DELTA_MS {
    MAX_DELTA_MS
  } else {
    raw_delta
  }
  self.last_ms = now_ms
  if confidence < MIN_CONFIDENCE {
    // 看不清就不推进任何状态：宁可漏计，不可误计。
    self.armed = false
    return self.snapshot(LowConfidence, confidence)
  }
  if self.plan.is_hold_only() {
    self.update_hold(frame, delta, confidence)
  } else {
    self.update_reps(frame, delta, now_ms, confidence)
  }
}

///|
/// 等长动作：只看「是否一直在正确的位置上」，破坏姿态则重新计时。
fn RepCounter::update_hold(
  self : RepCounter,
  frame : PoseFrame,
  delta : Int,
  confidence : Double,
) -> CounterSnapshot {
  let cycle = self.plan.cycle_phases()
  let phase = if cycle.length() > 0 { cycle[0] } else { empty_phase() }
  let satisfied = phase_satisfied(phase, frame, self.plan.hysteresis, false)
  if satisfied {
    self.held_ms = self.held_ms + delta
  } else {
    self.held_ms = 0
  }
  let second = self.held_ms / 1000
  if second > self.last_tick_second && second > 0 {
    self.last_tick_second = second
    self.snapshot(HoldTick(second), confidence)
  } else {
    self.snapshot(Idle, confidence)
  }
}

///|
/// 重复动作：相位推进 + 完整循环一次记 1 次。
fn RepCounter::update_reps(
  self : RepCounter,
  frame : PoseFrame,
  delta : Int,
  now_ms : Int,
  confidence : Double,
) -> CounterSnapshot {
  let cycle = self.plan.cycle_phases()
  if cycle.length() == 0 {
    return self.snapshot(Idle, confidence)
  }
  let index = self.phase_index % cycle.length()
  let phase = cycle[index]
  let hit = phase_satisfied(phase, frame, self.plan.hysteresis, false)
  let relaxed = phase_satisfied(phase, frame, self.plan.hysteresis, true)
  if hit {
    if !self.armed {
      self.armed = true
      self.dwell_ms = 0
    }
    self.dwell_ms = self.dwell_ms + delta
    if self.dwell_ms >= phase.hold_ms {
      self.phase_index = index + 1
      self.dwell_ms = 0
      self.armed = false
      if self.phase_index >= cycle.length() {
        self.phase_index = 0
        if now_ms - self.last_rep_ms >= self.plan.min_rep_ms {
          self.reps = self.reps + 1
          self.last_rep_ms = now_ms
          return self.snapshot(CompletedRep(self.reps), confidence)
        }
        return self.snapshot(Idle, confidence)
      }
      return self.snapshot(EnteredPhase(cycle[self.phase_index].id), confidence)
    }
    return self.snapshot(Idle, confidence)
  } else if relaxed && self.armed {
    // 落在滞回带里：保持当前相位、不给 dwell 累加时间，
    // 既不会因为抖动而回退相位，也不会因为抖动而凑满保持时长。
    return self.snapshot(Idle, confidence)
  } else {
    self.armed = false
    self.dwell_ms = 0
    return self.snapshot(Idle, confidence)
  }
}

///|
/// 相位（重载版：直接用当前相位 id 填快照）。
fn RepCounter::snapshot(
  self : RepCounter,
  event : CounterEvent,
  confidence : Double,
) -> CounterSnapshot {
  let cycle = self.plan.cycle_phases()
  let index = if cycle.length() > 0 {
    self.phase_index % cycle.length()
  } else {
    0
  }
  let phase_id = if cycle.length() > 0 { cycle[index].id } else { "" }
  let hold_ms = if cycle.length() > 0 { cycle[index].hold_ms } else { 0 }
  let progress = if self.plan.is_hold_only() {
    safe_div(self.held_ms.to_double(), self.plan.hold_only_ms.to_double(), 0.0)
  } else {
    safe_div(self.dwell_ms.to_double(), hold_ms.to_double(), 0.0)
  }
  {
    motion_id: self.plan.id,
    phase_id,
    phase_index: index,
    reps: self.reps,
    dwell_ms: self.dwell_ms,
    held_ms: self.held_ms,
    progress: progress.clamp(min=0.0, max=1.0),
    confidence,
    is_hold_only: self.plan.is_hold_only(),
    event,
  }
}

///|
/// 相位内全部约束是否成立。
///
/// `relaxed = false`：严格阈值，用于「进入/推进」；
/// `relaxed = true` ：放宽 hysteresis，用于「维持」。
fn phase_satisfied(
  phase : PhaseSpec,
  frame : PoseFrame,
  hysteresis : Double,
  relaxed : Bool,
) -> Bool {
  for target in phase.targets {
    match metric_value(target.metric, frame) {
      Some(observed) =>
        if relaxed {
          if !target.satisfied_with_hysteresis(observed, hysteresis) {
            return false
          }
        } else if !target.satisfied_by(observed) {
          return false
        }
      None => return false
    }
  }
  true
}

///|
/// 占位相位：动作没有声明任何相位时使用。
pub fn empty_phase() -> PhaseSpec {
  { id: "", targets: [], hold_ms: 0, }
}
