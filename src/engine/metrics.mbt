// MoveMentor 核心引擎 · 指标注册表
//
// 「指标」是这个引擎里唯一被 DSL 与人群约束引用的量：一个从 PoseFrame 算出来的
// Double。动作定义、人群能力、计数状态机全都只通过指标名耦合，
// 所以新增一个可被识别的自由度 = 在这里加一个分支，其余代码不动。
//
// 选指标的取舍：只挑正面机位下稳定的量。
//   - 角度类（knee_* / hip_* / shoulder_* / elbow_*）：三点夹角，正面下可用于
//     左右对称性的判断；正前方看不到屈膝深度，所以深蹲改用 hip_height_ratio。
//   - 比例类（ankle_span / knee_lift_* / wrist_above_shoulder_* /
//     hip_height_ratio）：用肩宽或躯干长做归一化，抵消机位远近和人高差异。
// 若换成 30°~45° 侧向机位，`knee_left` / `knee_right` 的屈膝读数会更有信息量，
// 动作 DSL 无需改动即可直接引用。

///|
/// 引擎内置的全部指标名（字典序稳定，便于文档与测试）。
pub fn metric_names() -> Array[String] {
  [
    "ankle_span", "confidence", "elbow_left", "elbow_right", "hip_height_ratio",
    "hip_left", "hip_right", "knee_left", "knee_lift_left", "knee_lift_right", "knee_right",
    "shoulder_left", "shoulder_right", "shin_drop_left", "shin_drop_right", "trunk_lean",
    "wrist_above_shoulder_left", "wrist_above_shoulder_right",
  ]
}

///|
/// 指标的中文短名，供界面与日志使用。
pub fn metric_label(name : String) -> String {
  match name {
    "knee_left" => "左膝夹角"
    "knee_right" => "右膝夹角"
    "hip_left" => "左髋夹角"
    "hip_right" => "右髋夹角"
    "shoulder_left" => "左肩外展"
    "shoulder_right" => "右肩外展"
    "elbow_left" => "左肘夹角"
    "elbow_right" => "右肘夹角"
    "trunk_lean" => "躯干倾角"
    "ankle_span" => "双脚开度（肩宽倍数）"
    "knee_lift_left" => "左膝抬升（踝髋距倍数）"
    "knee_lift_right" => "右膝抬升（踝髋距倍数）"
    "shin_drop_left" => "左小腿下垂（躯干长倍数）"
    "shin_drop_right" => "右小腿下垂（躯干长倍数）"
    "wrist_above_shoulder_left" => "左手高于肩（躯干长倍数）"
    "wrist_above_shoulder_right" => "右手高于肩（躯干长倍数）"
    "hip_height_ratio" => "髋高比（站坐程度）"
    "confidence" => "关键点平均可见度"
    _ => name
  }
}

///|
/// 指标名是否在注册表内。DSL 解析期用它拦截拼错的名字。
pub fn is_known_metric(name : String) -> Bool {
  for known in metric_names() {
    if known == name {
      return true
    }
  }
  false
}

///|
/// 求一个指标的值。名字未知时返回 `None`。
pub fn metric_value(name : String, frame : PoseFrame) -> Double? {
  let value = if name == "knee_left" {
    angle_deg_at(frame.get(LeftHip), frame.get(LeftKnee), frame.get(LeftAnkle))
  } else if name == "knee_right" {
    angle_deg_at(
      frame.get(RightHip),
      frame.get(RightKnee),
      frame.get(RightAnkle),
    )
  } else if name == "hip_left" {
    angle_deg_at(
      frame.get(LeftShoulder),
      frame.get(LeftHip),
      frame.get(LeftKnee),
    )
  } else if name == "hip_right" {
    angle_deg_at(
      frame.get(RightShoulder),
      frame.get(RightHip),
      frame.get(RightKnee),
    )
  } else if name == "shoulder_left" {
    angle_deg_at(
      frame.get(LeftHip),
      frame.get(LeftShoulder),
      frame.get(LeftElbow),
    )
  } else if name == "shoulder_right" {
    angle_deg_at(
      frame.get(RightHip),
      frame.get(RightShoulder),
      frame.get(RightElbow),
    )
  } else if name == "elbow_left" {
    angle_deg_at(
      frame.get(LeftShoulder),
      frame.get(LeftElbow),
      frame.get(LeftWrist),
    )
  } else if name == "elbow_right" {
    angle_deg_at(
      frame.get(RightShoulder),
      frame.get(RightElbow),
      frame.get(RightWrist),
    )
  } else if name == "trunk_lean" {
    trunk_lean_deg(frame)
  } else if name == "ankle_span" {
    ankle_span_ratio(frame)
  } else if name == "knee_lift_left" {
    knee_lift_ratio(frame, LeftHip, LeftKnee, LeftAnkle)
  } else if name == "knee_lift_right" {
    knee_lift_ratio(frame, RightHip, RightKnee, RightAnkle)
  } else if name == "shin_drop_left" {
    shin_drop_ratio(frame, LeftKnee, LeftAnkle)
  } else if name == "shin_drop_right" {
    shin_drop_ratio(frame, RightKnee, RightAnkle)
  } else if name == "wrist_above_shoulder_left" {
    wrist_above_shoulder_ratio(frame, LeftShoulder, LeftWrist)
  } else if name == "wrist_above_shoulder_right" {
    wrist_above_shoulder_ratio(frame, RightShoulder, RightWrist)
  } else if name == "hip_height_ratio" {
    hip_height_ratio(frame)
  } else if name == "confidence" {
    frame.tracked_visibility()
  } else {
    return None
  }
  Some(value)
}

///|
/// 躯干相对竖直方向的倾斜角：肩中点指向髋中点的方向与「正下方」的夹角。
pub fn trunk_lean_deg(frame : PoseFrame) -> Double {
  let shoulder_mid = frame.midpoint_of(LeftShoulder, RightShoulder)
  let hip_mid = frame.midpoint_of(LeftHip, RightHip)
  tilt_from_vertical_deg(hip_mid.x - shoulder_mid.x, hip_mid.y - shoulder_mid.y)
}

///|
/// 双脚开度，以肩宽为单位。站立并脚约 0，两脚分开约 2~4。
pub fn ankle_span_ratio(frame : PoseFrame) -> Double {
  let ankle_span = (frame.get(LeftAnkle).x - frame.get(RightAnkle).x).abs()
  let shoulder_span = (frame.get(LeftShoulder).x - frame.get(RightShoulder).x).abs()
  safe_div(ankle_span, shoulder_span, 0.0)
}

///|
/// 抬膝程度：髋到膝的竖直距离 ÷ 髋到踝的竖直距离。
/// 完全站立时膝在髋正下方约 0.5，抬到髋高附近时接近 1.0。
pub fn knee_lift_ratio(
  frame : PoseFrame,
  hip : Joint,
  knee : Joint,
  ankle : Joint,
) -> Double {
  let h = frame.get(hip)
  let k = frame.get(knee)
  let a = frame.get(ankle)
  safe_div(h.y - k.y, (a.y - h.y).abs(), 0.0)
}

///|
/// 小腿相对膝关节的下垂程度，以躯干长为单位。
///
/// 坐姿垂腿约 2.0，抬到接近水平约 0.6，抬过水平继续下降至负数。
/// 这是坐姿抬腿类动作最稳的读数：它只依赖膝与踝的相对高度，
/// 对髋部在画面里的绝对位置不敏感。
pub fn shin_drop_ratio(
  frame : PoseFrame,
  knee : Joint,
  ankle : Joint,
) -> Double {
  let shoulder_mid = frame.midpoint_of(LeftShoulder, RightShoulder)
  let hip_mid = frame.midpoint_of(LeftHip, RightHip)
  let torso = (hip_mid.y - shoulder_mid.y).abs()
  safe_div(frame.get(ankle).y - frame.get(knee).y, torso, 0.0)
}

///|
/// 手腕高出肩多少，以躯干长（肩到髋的竖直距离）为单位。
/// 手在肩下方时为负，举过头顶时为正。
pub fn wrist_above_shoulder_ratio(
  frame : PoseFrame,
  shoulder : Joint,
  wrist : Joint,
) -> Double {
  let s = frame.get(shoulder)
  let w = frame.get(wrist)
  let hip_mid = frame.midpoint_of(LeftHip, RightHip)
  safe_div(s.y - w.y, (hip_mid.y - s.y).abs(), 0.0)
}

///|
/// 髋高比：踝中点到髋中点的距离 ÷ 踝中点到肩中点的距离。
///
/// 站立约 0.78~0.85，下蹲时肩随髋一起下沉但踝不动，比值随之下降。
/// 这是正面机位下判断「站起来了没有 / 蹲下去了没有」最稳的量。
pub fn hip_height_ratio(frame : PoseFrame) -> Double {
  let shoulder_mid = frame.midpoint_of(LeftShoulder, RightShoulder)
  let hip_mid = frame.midpoint_of(LeftHip, RightHip)
  let ankle_mid = frame.midpoint_of(LeftAnkle, RightAnkle)
  safe_div(ankle_mid.y - hip_mid.y, ankle_mid.y - shoulder_mid.y, 0.0)
}
