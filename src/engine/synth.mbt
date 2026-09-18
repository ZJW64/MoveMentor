// MoveMentor 核心引擎 · 合成姿态源
//
// 为什么要有一个「假人」？
//   1. 计数器、翻译器、指导语全部要有测试，而测试不该依赖摄像头或网络；
//   2. 现场演示最怕翻车（没有摄像头权限、浏览器不给网络、评委电脑没有摄像头），
//      有了合成源，「演示模式」在任何一台机器上都能跑完整条流水线。
//
// 它不是什么：不是动作识别，也不是物理仿真。它只是按动作 DSL 里声明的阈值，
// 反推出几条能跨过这些阈值的骨架轨迹——够用、可复现、可断言，如此而已。
//
// 关键设计：合成参数由 DSL 的阈值推导，而不是写死。
// 改了 DSL 里的阈值，合成轨迹自动跟着改，测试不需要同步改数据。

///|
/// 合成骨架的参数化描述。默认值是一副自然站立的骨架：
/// 肩宽 0.12、躯干长 0.12，踝在 y = 0.90，身高用归一化图像坐标表示。
pub(all) struct SkeletonParams {
  mut shoulder_y : Double
  mut shoulder_half : Double
  mut elbow_y : Double
  mut elbow_half : Double
  mut wrist_y : Double
  mut wrist_half : Double
  mut hip_y : Double
  mut hip_half : Double
  mut knee_y : Double
  mut knee_half : Double
  mut ankle_y : Double
  mut ankle_half : Double
  mut body_lean_deg : Double
  mut drive_left : Bool
  mut drive_right : Bool
} derive(Debug)

///|
pub fn SkeletonParams::standing() -> SkeletonParams {
  {
    shoulder_y: 0.30,
    shoulder_half: 0.06,
    elbow_y: 0.42,
    elbow_half: 0.055,
    wrist_y: 0.54,
    wrist_half: 0.06,
    hip_y: 0.42,
    hip_half: 0.035,
    knee_y: 0.66,
    knee_half: 0.03,
    ankle_y: 0.90,
    ankle_half: 0.03,
    body_lean_deg: 0.0,
    drive_left: true,
    drive_right: true,
  }
}

///|
/// 坐姿骨架：髋抬到椅面高度 0.62，躯干缩短到 0.12，小腿自然下垂。
pub fn SkeletonParams::seated() -> SkeletonParams {
  let params = SkeletonParams::standing()
  params.hip_y = 0.62
  params.shoulder_y = 0.50
  params.elbow_y = 0.62
  params.wrist_y = 0.74
  params.hip_half = 0.045
  params.knee_half = 0.055
  params.ankle_half = 0.055
  params
}

///|
fn point(x : Double, y : Double) -> Landmark {
  Landmark::new(x, y, 0.0, 1.0)
}

///|
/// 绕 `pivot` 旋转 `deg` 度（顺时针为正，因为 y 轴向下）。
fn rotate_about(p : Landmark, pivot : Landmark, deg : Double) -> Landmark {
  let rad = deg * 3.141592653589793 / 180.0
  let c = @math.cos(rad)
  let s = @math.sin(rad)
  let dx = p.x - pivot.x
  let dy = p.y - pivot.y
  point(pivot.x + dx * c - dy * s, pivot.y + dx * s + dy * c)
}

///|
pub fn lerp(a : Double, b : Double, s : Double) -> Double {
  a + (b - a) * s
}

///|
/// 未被驱动的腿所使用的静息位置（坐姿垂腿）。
const REST_KNEE_Y : Double = 0.66

///|
const REST_ANKLE_Y : Double = 0.90

///|
/// 把参数摊成一帧姿态。
///
/// `body_lean_deg` 是整体刚性旋转：绕髋中点为轴，整个身体一起转。
/// 对靠墙站立这类动作它接近 0，对平板支撑这类动作它接近 90——
/// 因此同一个参数既能表达「站直」也能表达「身体水平」。
///
/// `drive_left` / `drive_right` 用于单侧动作：没被驱动的那条腿停在
/// 坐姿静息位，这样「坐姿抬腿」在合成数据里也确实是单腿在动。
pub fn SkeletonParams::to_frame(self : SkeletonParams) -> PoseFrame {
  let frame = PoseFrame::empty()
  let center = 0.5
  let pivot = point(center, self.hip_y)
  let lean = self.body_lean_deg
  let put = fn(joint : Joint, p : Landmark) {
    frame.set(joint, rotate_about(p, pivot, lean))
  }
  let left_knee_y = if self.drive_left { self.knee_y } else { REST_KNEE_Y }
  let left_ankle_y = if self.drive_left { self.ankle_y } else { REST_ANKLE_Y }
  let right_knee_y = if self.drive_right { self.knee_y } else { REST_KNEE_Y }
  let right_ankle_y = if self.drive_right { self.ankle_y } else { REST_ANKLE_Y }
  put(LeftShoulder, point(center - self.shoulder_half, self.shoulder_y))
  put(RightShoulder, point(center + self.shoulder_half, self.shoulder_y))
  put(LeftElbow, point(center - self.elbow_half, self.elbow_y))
  put(RightElbow, point(center + self.elbow_half, self.elbow_y))
  put(LeftWrist, point(center - self.wrist_half, self.wrist_y))
  put(RightWrist, point(center + self.wrist_half, self.wrist_y))
  put(LeftHip, point(center - self.hip_half, self.hip_y))
  put(RightHip, point(center + self.hip_half, self.hip_y))
  put(LeftKnee, point(center - self.knee_half, left_knee_y))
  put(RightKnee, point(center + self.knee_half, right_knee_y))
  put(LeftAnkle, point(center - self.ankle_half, left_ankle_y))
  put(RightAnkle, point(center + self.ankle_half, right_ankle_y))
  frame
}

///|
/// 合成轨迹的骨架原型。由动作声明的指标集合推断。
pub(all) enum Archetype {
  SeatedLegLift
  StandingBilateral
  Squat
  SeatedArmRaise
  LeanHold
} derive(Debug, Eq)

///|
/// 稳定的小写标识符，用于日志与测试断言。
pub fn Archetype::token(self : Archetype) -> String {
  match self {
    SeatedLegLift => "seated_leg_lift"
    StandingBilateral => "standing_bilateral"
    Squat => "squat"
    SeatedArmRaise => "seated_arm_raise"
    LeanHold => "lean_hold"
  }
}

///|
/// 动作里是否引用了某个指标。
pub fn has_target(plan : MotionSpec, metric : String) -> Bool {
  for p in plan.phases {
    for t in p.targets {
      if t.metric == metric {
        return true
      }
    }
  }
  false
}

///|
/// 该动作对所有 `>=` 约束中最高的那个值。用于推断「动作做到位」的目标。
pub fn highest_at_least(plan : MotionSpec, metric : String) -> Double? {
  let mut best : Double? = None
  for p in plan.phases {
    for t in p.targets {
      if t.metric == metric && t.cmp == AtLeast {
        match best {
          Some(v) => if t.value > v { best = Some(t.value) }
          None => best = Some(t.value)
        }
      }
    }
  }
  best
}

///|
/// 该动作对所有 `<=` 约束中最低的那个值。用于推断「回到起始位」的目标。
pub fn lowest_at_most(plan : MotionSpec, metric : String) -> Double? {
  let mut best : Double? = None
  for p in plan.phases {
    for t in p.targets {
      if t.metric == metric && t.cmp == AtMost {
        match best {
          Some(v) => if t.value < v { best = Some(t.value) }
          None => best = Some(t.value)
        }
      }
    }
  }
  best
}

///|
/// 按指标集合推断骨架原型。顺序即优先级，改动顺序会改变演示行为。
pub fn archetype_of(plan : MotionSpec) -> Archetype {
  if has_target(plan, "shin_drop_left") || has_target(plan, "shin_drop_right") {
    SeatedLegLift
  } else if has_target(plan, "ankle_span") {
    StandingBilateral
  } else if has_target(plan, "trunk_lean") {
    LeanHold
  } else if has_target(plan, "hip_height_ratio") {
    Squat
  } else if has_target(plan, "wrist_above_shoulder_left") ||
    has_target(plan, "wrist_above_shoulder_right") {
    SeatedArmRaise
  } else {
    StandingBilateral
  }
}

///|
/// 由动作声明推出「站立位髋高比」。
fn standing_ratio(plan : MotionSpec) -> Double {
  match highest_at_least(plan, "hip_height_ratio") {
    Some(v) => v
    None => 0.80
  }
}

///|
/// 髋高比 → 髋的 y 坐标。躯干长固定为 `torso`，脚固定在 `ankle_y`。
fn hip_y_for_ratio(ratio : Double, ankle_y : Double, torso : Double) -> Double {
  let safe = ratio.clamp(min=0.05, max=0.95)
  (ankle_y - (ankle_y + torso) * safe) / (1.0 - safe)
}

///|
/// 合成的「做到位」一侧要比阈值多走一点：如果合成值恰好落在阈值上，
/// 浮点误差足以让 `>=` 判定翻车。`>=` 一侧往更大的方向多走 15%。
fn overshoot_up(value : Double) -> Double {
  if value > 0.0 {
    value * 1.15
  } else {
    value + 0.15
  }
}

///|
/// 合成的「回到起始位」一侧同理，`<=` 一侧往更小的方向多走 15%。
fn overshoot_down(value : Double) -> Double {
  if value > 0.0 {
    value * 0.85
  } else {
    value - 0.15
  }
}

///|
/// 读取一个 `>=` 阈值，缺省时用 `fallback`。
fn at_least_or(plan : MotionSpec, metric : String, fallback : Double) -> Double {
  match highest_at_least(plan, metric) {
    Some(v) => v
    None => fallback
  }
}

///|
/// 读取一个 `<=` 阈值，缺省时用 `fallback`。
fn at_most_or(plan : MotionSpec, metric : String, fallback : Double) -> Double {
  match lowest_at_most(plan, metric) {
    Some(v) => v
    None => fallback
  }
}

///|
/// 给定原型与进度 `s`（0 = 起始位，1 = 做到位），生成骨架参数。
pub fn synth_params(
  archetype : Archetype,
  plan : MotionSpec,
  s : Double,
) -> SkeletonParams {
  match archetype {
    StandingBilateral => {
      let params = SkeletonParams::standing()
      let open_span = overshoot_up(at_least_or(plan, "ankle_span", 1.6))
      let close_span = overshoot_down(at_most_or(plan, "ankle_span", 0.6))
      params.ankle_half = lerp(close_span, open_span, s) * params.shoulder_half
      if has_target(plan, "wrist_above_shoulder_left") {
        let up = overshoot_up(
          at_least_or(plan, "wrist_above_shoulder_left", 1.0),
        )
        let down = overshoot_down(
          at_most_or(plan, "wrist_above_shoulder_left", -1.5),
        )
        let torso = params.hip_y - params.shoulder_y
        params.wrist_y = params.shoulder_y - lerp(down, up, s) * torso
        params.wrist_half = lerp(0.06, 0.20, s)
        params.elbow_y = (params.shoulder_y + params.wrist_y) / 2.0
        params.elbow_half = lerp(0.055, 0.13, s)
      }
      params
    }
    Squat => {
      let params = SkeletonParams::standing()
      let torso = params.hip_y - params.shoulder_y
      let top = standing_ratio(plan) + 0.012
      let bottom = at_most_or(plan, "hip_height_ratio", top - 0.05) - 0.012
      let ratio = lerp(top, bottom, s)
      params.hip_y = hip_y_for_ratio(ratio, params.ankle_y, torso)
      params.shoulder_y = params.hip_y - torso
      params.knee_y = lerp(0.66, 0.72, s)
      params.knee_half = lerp(0.03, 0.08, s)
      params.ankle_half = lerp(0.03, 0.05, s)
      params
    }
    SeatedLegLift => {
      let params = SkeletonParams::seated()
      let torso = params.hip_y - params.shoulder_y
      let rest_drop = at_least_or(plan, "shin_drop_right", 2.0) + 0.25
      let active_drop = at_most_or(plan, "shin_drop_right", 0.7) - 0.10
      let knee_y = lerp(0.66, 0.50, s)
      let drop = lerp(rest_drop, active_drop, s)
      params.drive_left = has_target(plan, "shin_drop_left")
      params.drive_right = has_target(plan, "shin_drop_right")
      params.knee_y = knee_y
      params.ankle_y = knee_y + drop * torso
      params
    }
    SeatedArmRaise => {
      let params = SkeletonParams::seated()
      let torso = params.hip_y - params.shoulder_y
      let up = overshoot_up(
        at_least_or(plan, "wrist_above_shoulder_right", 0.5),
      )
      let down = overshoot_down(
        at_most_or(plan, "wrist_above_shoulder_right", -1.5),
      )
      params.wrist_y = params.shoulder_y - lerp(down, up, s) * torso
      params.wrist_half = lerp(0.06, 0.16, s)
      params.elbow_y = (params.shoulder_y + params.wrist_y) / 2.0
      params.elbow_half = lerp(0.07, 0.11, s)
      params
    }
    LeanHold => {
      let params = SkeletonParams::standing()
      let base = match highest_at_least(plan, "trunk_lean") {
        Some(v) => v + 8.0
        None =>
          match lowest_at_most(plan, "trunk_lean") {
            Some(v) => v - 3.0
            None => 2.0
          }
      }
      params.body_lean_deg = base + 1.2 * @math.sin(6.283185307179586 * s)
      params
    }
  }
}

///|
/// 合成轨迹的周期（毫秒）。
///
/// 由各相位的保持时长推导：相位要求保持越久，合成轨迹越慢。
/// 这样「计数器刚好能数出来」与「动作看起来不赶」是同一个旋钮。
pub fn synth_period_ms(plan : MotionSpec) -> Int {
  if plan.is_hold_only() {
    2000
  } else {
    let mut dwell = 0
    for p in plan.cycle_phases() {
      dwell = dwell + p.hold_ms
    }
    let candidate = 2 * (dwell + 400)
    if candidate < 1600 {
      1600
    } else {
      candidate
    }
  }
}

///|
/// 梯形波：上升 20%，上平台 30%，下降 20%，下平台 30%。
///
/// 为什么不用正弦：正弦在两个极值点附近只停留很短的时间，而动作 DSL 里的
/// `hold` 要求「在到位姿态上保持多久」。用正弦会出现「波形到了极值但保持不够」
/// 的假阴性——合成数据自己过不了自己的阈值。梯形波在两端有真实的保持区，
/// 也更接近真人做动作的节律（到位—停一下—回位—停一下）。
fn trapezoid(phase : Double) -> Double {
  if phase < 0.20 {
    ease(phase / 0.20)
  } else if phase < 0.50 {
    1.0
  } else if phase < 0.70 {
    ease(1.0 - (phase - 0.50) / 0.20)
  } else {
    0.0
  }
}

///|
/// 平滑过渡：`u = 0` 时为 0，`u = 1` 时为 1，两端一阶导数为 0。
fn ease(u : Double) -> Double {
  let clamped = u.clamp(min=0.0, max=1.0)
  0.5 - 0.5 * @math.cos(3.141592653589793 * clamped)
}

///|
/// 合成第 `t_ms` 毫秒的一帧。
///
/// 等长动作停在「做到位」的位置上（`s = 1`）；重复动作按梯形波在 0 与 1 之间往返，
/// 一个完整周期对应一次重复。
pub fn synth_frame(plan : MotionSpec, t_ms : Int) -> PoseFrame {
  let archetype = archetype_of(plan)
  let s = if plan.is_hold_only() {
    1.0
  } else {
    let period = synth_period_ms(plan).to_double()
    trapezoid(t_ms.to_double() % period / period)
  }
  synth_params(archetype, plan, s).to_frame()
}
