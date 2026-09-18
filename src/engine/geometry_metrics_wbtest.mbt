// 几何与指标的白盒测试。
//
// 这一层是纯函数，是整套引擎里最应该被测透的部分：
// 计次、翻译、校验全都建立在「指标算得对」之上。

///|
test "angular: 直角与共线" {
  let a = Landmark::new(0.0, 0.0, 0.0, 1.0)
  let vertex = Landmark::new(0.0, 1.0, 0.0, 1.0)
  let c = Landmark::new(1.0, 1.0, 0.0, 1.0)
  assert_true(almost_equal(angle_deg_at(a, vertex, c), 90.0, 0.001))
  let straight = Landmark::new(0.0, 2.0, 0.0, 1.0)
  assert_true(almost_equal(angle_deg_at(a, vertex, straight), 180.0, 0.001))
}

///|
test "angular: 退化输入返回 0 而不是 NaN" {
  let p = Landmark::new(0.3, 0.3, 0.0, 1.0)
  let q = Landmark::new(0.3, 0.3, 0.0, 1.0)
  assert_true(almost_equal(angle_deg_at(p, q, p), 0.0, 0.0001))
}

///|
test "tilt: 竖直为 0，水平为 90" {
  assert_true(almost_equal(tilt_from_vertical_deg(0.0, 1.0), 0.0, 0.001))
  assert_true(almost_equal(tilt_from_vertical_deg(1.0, 0.0), 90.0, 0.001))
  assert_true(almost_equal(tilt_from_vertical_deg(-1.0, 0.0), 90.0, 0.001))
  // 45 度
  assert_true(almost_equal(tilt_from_vertical_deg(1.0, 1.0), 45.0, 0.001))
}

///|
test "safe_div: 分母为 0 时返回退路值" {
  assert_true(almost_equal(safe_div(1.0, 0.0, 7.0), 7.0, 0.0001))
  assert_true(almost_equal(safe_div(6.0, 3.0, 7.0), 2.0, 0.0001))
}

///|
test "metrics: 指标名清单自洽" {
  let names = metric_names()
  assert_eq(names.length(), 18)
  for name in names {
    assert_true(is_known_metric(name))
  }
  assert_true(!is_known_metric("knee_flexion"))
  assert_true(!is_known_metric(""))
}

///|
test "metrics: 未知指标返回 None" {
  assert_eq(metric_value("no_such_metric", standing_frame()), None)
}

///|
test "metrics: 站姿的基线读数" {
  let frame = standing_frame()
  // 肩宽 0.12、踝距 0.06 → 0.5
  assert_true(
    almost_equal(metric_value("ankle_span", frame).unwrap(), 0.5, 0.001),
  )
  // 肩 0.30、髋 0.42、踝 0.90 → (0.90-0.42)/(0.90-0.30) = 0.8
  assert_true(
    almost_equal(metric_value("hip_height_ratio", frame).unwrap(), 0.8, 0.001),
  )
  // 站直 → 躯干倾角 0
  assert_true(
    almost_equal(metric_value("trunk_lean", frame).unwrap(), 0.0, 0.001),
  )
  // 手腕在肩下方 0.24，躯干长 0.12 → -2.0
  assert_true(
    almost_equal(
      metric_value("wrist_above_shoulder_left", frame).unwrap(),
      -2.0,
      0.001,
    ),
  )
  // 小腿下垂：(0.90 - 0.66)/0.12 = 2.0
  assert_true(
    almost_equal(metric_value("shin_drop_left", frame).unwrap(), 2.0, 0.001),
  )
  // 抬膝：(0.42 - 0.66)/0.48 = -0.5
  assert_true(
    almost_equal(metric_value("knee_lift_left", frame).unwrap(), -0.5, 0.001),
  )
}

///|
test "metrics: 膝角随小腿前摆变小" {
  let straight = frame_of([
    (LeftHip, 0.465, 0.42),
    (LeftKnee, 0.47, 0.66),
    (LeftAnkle, 0.47, 0.90),
  ])
  let bent = frame_of([
    (LeftHip, 0.465, 0.42),
    (LeftKnee, 0.47, 0.66),
    (LeftAnkle, 0.62, 0.72),
  ])
  let straight_angle = metric_value("knee_left", straight).unwrap()
  let bent_angle = metric_value("knee_left", bent).unwrap()
  assert_true(straight_angle > 170.0)
  assert_true(bent_angle < 120.0)
  assert_true(bent_angle < straight_angle)
}

///|
test "metrics: 可见度只看引擎真正使用的 12 个点" {
  let frame = standing_frame()
  assert_true(almost_equal(frame.tracked_visibility(), 1.0, 0.0001))
  // 把画面里一个无关的点（鼻子，下标 0）拉低，不应影响判定
  frame.put_at(0, Landmark::new(0.5, 0.1, 0.0, 0.0))
  assert_true(almost_equal(frame.tracked_visibility(), 1.0, 0.0001))
  // 拉低一个真正使用的点则会下降
  frame.set(LeftKnee, Landmark::new(0.47, 0.66, 0.0, 0.0))
  assert_true(frame.tracked_visibility() < 1.0)
}

///|
test "landmark: 中点与平面距离" {
  let a = Landmark::new(0.0, 0.0, 0.0, 1.0)
  let b = Landmark::new(1.0, 0.0, 5.0, 1.0)
  let mid = a.midpoint(b)
  assert_true(almost_equal(mid.x, 0.5, 0.0001))
  assert_true(almost_equal(mid.y, 0.0, 0.0001))
  // z 不参与平面距离
  assert_true(almost_equal(a.planar_distance(b), 1.0, 0.0001))
}

///|
test "pose frame: 扁平数组长度校验" {
  assert_true(
    PoseFrame::from_flat(Array::make(POSE_POINT_COUNT * POSE_STRIDE, 0.0))
    is Some(_),
  )
  assert_true(PoseFrame::from_flat(Array::make(10, 0.0)) is None)
  assert_eq(POSE_POINT_COUNT, 33)
  assert_eq(POSE_STRIDE, 4)
}
