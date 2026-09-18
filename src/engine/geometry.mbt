// MoveMentor 核心引擎 · 几何计算
//
// 全部基于图像平面的 2D 投影。理由是：手机/笔记本前置摄像头几乎总是正面机位，
// 而 MediaPipe 的 z 分量在这个机位下并不稳定，直接拿三维向量算夹角会把噪声放大。
// 正面看不到的自由度（例如正面视角下的屈膝角度）由更稳的代理指标承担，
// 具体见 metrics.mbt 的注释。

///|
/// 以 `vertex` 为顶点，`a` 与 `c` 为两端的夹角（度，0..180）。
///
/// 三点退化（重合、零长度向量）时返回 0，而不是 NaN——上层据此判定「不可用」。
pub fn angle_deg_at(a : Landmark, vertex : Landmark, c : Landmark) -> Double {
  let v1x = a.x - vertex.x
  let v1y = a.y - vertex.y
  let v2x = c.x - vertex.x
  let v2y = c.y - vertex.y
  let n1 = (v1x * v1x + v1y * v1y).sqrt()
  let n2 = (v2x * v2x + v2y * v2y).sqrt()
  let denom = n1 * n2
  if denom <= 1.0e-9 {
    0.0
  } else {
    let cos = (dot2(v1x, v1y, v2x, v2y) / denom).clamp(min=-1.0, max=1.0)
    radians_to_deg(acos_safe(cos))
  }
}

///|
/// 二维点积。
pub fn dot2(ax : Double, ay : Double, bx : Double, by : Double) -> Double {
  ax * bx + ay * by
}

///|
/// `dx`、`dy` 描述的方向与竖直向下方向的夹角（度）。用于躯干倾角。
pub fn tilt_from_vertical_deg(dx : Double, dy : Double) -> Double {
  let len = (dx * dx + dy * dy).sqrt()
  if len <= 1.0e-9 {
    0.0
  } else {
    let cos = (dy / len).clamp(min=-1.0, max=1.0)
    radians_to_deg(acos_safe(cos))
  }
}

///|
/// 先夹到 [-1, 1] 再取反余弦，避免浮点误差把边界值推到定义域外。
pub fn acos_safe(x : Double) -> Double {
  @math.acos(x.clamp(min=-1.0, max=1.0))
}

///|
pub fn radians_to_deg(rad : Double) -> Double {
  rad * 180.0 / 3.141592653589793
}

///|
/// 保护性除法：分母接近 0 时返回 `fallback`。
pub fn safe_div(numer : Double, denom : Double, fallback : Double) -> Double {
  if denom.abs() <= 1.0e-9 {
    fallback
  } else {
    numer / denom
  }
}

///|
/// 两个浮点数在 `eps` 容差内是否相等。单元测试里代替 `==` 使用。
pub fn almost_equal(a : Double, b : Double, eps : Double) -> Bool {
  (a - b).abs() <= eps
}
