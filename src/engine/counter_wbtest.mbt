// 计数状态机的白盒测试。
//
// 计次是「看起来很傻、写起来很坑」的典型：真正要测的不是「正常人做动作能不能数对」，
// 而是三类异常输入：阈值附近的抖动、掉帧的时间跳变、关键点丢失。
// 这三类如果没测，演示当天就会出问题。

///|
/// 构造一帧：只控制双脚开度（以肩宽为单位），其余按标准站姿。
fn spanning_frame(span : Double) -> PoseFrame {
  let frame = standing_frame()
  let half = span * 0.06
  frame.set(LeftAnkle, Landmark::new(0.5 - half, 0.90, 0.0, 1.0))
  frame.set(RightAnkle, Landmark::new(0.5 + half, 0.90, 0.0, 1.0))
  frame
}

///|
/// 把所有被跟踪的关键点的可见度改成同一个值，用来模拟「画面里看不清人」。
fn veiled_frame(span : Double, visibility : Double) -> PoseFrame {
  let frame = spanning_frame(span)
  for joint in tracked_joints() {
    let p = frame.get(joint)
    frame.set(joint, Landmark::new(p.x, p.y, p.z, visibility))
  }
  frame
}

///|
/// 一个最小的开合类动作：`on` 要求开度 ≥ 0.5，`off` 要求开度 ≤ 0.3。
fn span_plan(
  hold_ms : Int,
  hysteresis : Double,
  min_rep_ms : Int,
) -> MotionSpec raise {
  let source = "motion span\nname 开度测试\nphase on hold=\{hold_ms} ankle_span>=0.5\nphase off hold=\{hold_ms} ankle_span<=0.3\ncycle on off\nhysteresis \{hysteresis}\nmin_rep_ms \{min_rep_ms}\n"
  let program = parse_program(source)
  assert_eq(program.issues.length(), 0)
  program.motions[0]
}

///|
test "counter: 起始状态是干净的空计数" {
  let counter = RepCounter::new(span_plan(200, 0.15, 500))
  let snapshot = counter.update(spanning_frame(0.2), 0)
  assert_eq(snapshot.reps, 0)
  assert_eq(snapshot.held_ms, 0)
  assert_eq(snapshot.event, Idle)
  assert_eq(snapshot.phase_id, "on")
  assert_true(almost_equal(snapshot.confidence, 1.0, 0.0001))
}

///|
test "counter: 滞回带里停留不累积保持时间" {
  let counter = RepCounter::new(span_plan(300, 0.15, 0))
  // 0.35 落在滞回带内（进入要 ≥0.5，维持放宽到 ≥0.35）：不应该被当成「进入相位」
  for i in 0..<30 {
    let snapshot = counter.update(spanning_frame(0.35), i * 33)
    assert_eq(snapshot.reps, 0)
    assert_eq(snapshot.dwell_ms, 0)
  }
  // 真正跨过严格阈值后才开始累计：11 帧 × 33ms ≈ 363ms，刚好够 300ms
  let mut last = counter.update(spanning_frame(0.35), 990)
  assert_eq(last.reps, 0)
  assert_eq(last.phase_id, "on")
  for i in 1..<12 {
    last = counter.update(spanning_frame(0.6), 990 + i * 33)
  }
  // 相位推进了 = 保持时间确实从严格命中的那一刻开始重新累计
  assert_eq(last.phase_id, "off")
}

///|
test "counter: 最小重复间隔能压掉高频误计" {
  let fast = span_plan(50, 0.05, 0)
  let throttled = span_plan(50, 0.05, 1000)
  let mut free_reps = 0
  let mut throttled_reps = 0
  let counter_free = RepCounter::new(fast)
  let counter_throttled = RepCounter::new(throttled)
  // 每 200ms 开、200ms 合，跑 10 秒：不设下限时会数出很多次
  for i in 0..<300 {
    let now = i * 33
    let open = now / 200 % 2 == 0
    let span = if open { 0.8 } else { 0.1 }
    free_reps = counter_free.update(spanning_frame(span), now).reps
    throttled_reps = counter_throttled.update(spanning_frame(span), now).reps
  }
  assert_true(free_reps >= 15)
  assert_true(throttled_reps <= 11)
  assert_true(throttled_reps < free_reps)
}

///|
test "counter: 关键点不可见时整帧作废" {
  let counter = RepCounter::new(span_plan(100, 0.10, 0))
  let snapshot = counter.update(veiled_frame(0.9, 0.2), 0)
  assert_eq(snapshot.event, LowConfidence)
  assert_eq(snapshot.reps, 0)
  assert_eq(snapshot.dwell_ms, 0)
  assert_true(snapshot.confidence < MIN_CONFIDENCE)
}

///|
test "counter: 掉帧导致的时间跳变被钳位" {
  let plan = builtin_motion(builtin_program(), "wall_body_hold")
  let counter = RepCounter::new(plan)
  let frame = synth_frame(plan, 0)
  let _ = counter.update(frame, 0)
  // 模拟切后台 100 秒后回来的一帧：最多只应计入 MAX_DELTA_MS
  let snapshot = counter.update(frame, 100000)
  assert_true(snapshot.held_ms <= MAX_DELTA_MS)
}

///|
test "counter: 等长动作保持与中断" {
  let plan = builtin_motion(builtin_program(), "wall_body_hold")
  let counter = RepCounter::new(plan)
  let good = synth_frame(plan, 0)
  let mut snapshot = counter.update(good, 0)
  let ticks : Array[Int] = []
  for i in 1..<60 {
    snapshot = counter.update(good, i * 33)
    match snapshot.event {
      HoldTick(second) => ticks.push(second)
      _ => ()
    }
  }
  assert_true(snapshot.held_ms > 1500)
  assert_true(snapshot.held_ms <= 2000)
  assert_eq(ticks.length(), 1)
  assert_eq(ticks[0], 1)
  // 姿态被破坏（躯干倾角远超阈值 + 滞回）后必须重新计时
  let leaned = synth_params(LeanHold, plan, 0).to_frame()
  leaned.set(LeftShoulder, Landmark::new(0.44, 0.30, 0.0, 1.0))
  leaned.set(RightShoulder, Landmark::new(0.56, 0.30, 0.0, 1.0))
  leaned.set(LeftHip, Landmark::new(0.30, 0.60, 0.0, 1.0))
  leaned.set(RightHip, Landmark::new(0.42, 0.60, 0.0, 1.0))
  snapshot = counter.update(leaned, 60 * 33)
  assert_eq(snapshot.held_ms, 0)
}

///|
test "counter: 重置后回到初始状态" {
  let plan = builtin_motion(builtin_program(), "jumping_jack")
  let counter = RepCounter::new(plan)
  let mut snapshot = counter.update(synth_frame(plan, 0), 0)
  for i in 1..<90 {
    snapshot = counter.update(synth_frame(plan, i * 33), i * 33)
  }
  assert_true(snapshot.reps >= 1)
  counter.reset()
  assert_eq(counter.reps, 0)
  assert_eq(counter.held_ms, 0)
  assert_eq(counter.phase_index, 0)
}

///|
test "counter: 合成姿态端到端计次（开合跳 12 秒 7 次）" {
  let plan = builtin_motion(builtin_program(), "jumping_jack")
  let snapshot = simulate(plan, 12)
  // 开合跳两相位各保持 180ms → 合成周期被抬到下限 1600ms，12 秒内约 7 次。
  assert_eq(snapshot.reps, 7)
}

///|
test "counter: 合成姿态端到端计次（坐姿抬腿 12 秒 6 次）" {
  let plan = builtin_motion(builtin_program(), "seated_leg_lift")
  let snapshot = simulate(plan, 12)
  assert_eq(snapshot.reps, 6)
}

///|
test "counter: 合成姿态端到端计次（扶椅浅蹲 12 秒 6 次）" {
  let plan = builtin_motion(builtin_program(), "chair_squat")
  let snapshot = simulate(plan, 12)
  assert_eq(snapshot.reps, 6)
}

///|
test "counter: 等长动作端到端计时（靠墙直立 12 秒）" {
  let plan = builtin_motion(builtin_program(), "wall_body_hold")
  let snapshot = simulate(plan, 12)
  assert_eq(snapshot.is_hold_only, true)
  assert_eq(snapshot.reps, 0)
  assert_true(snapshot.held_ms >= 11000)
  assert_true(snapshot.held_ms <= 12000)
}

///|
test "counter: 每组动作用合成姿态跑 20 秒都不出异常" {
  let program = builtin_program()
  for motion in program.motions {
    let snapshot = simulate(motion, 20)
    assert_true(snapshot.confidence > MIN_CONFIDENCE)
    assert_true(snapshot.progress >= 0.0)
    assert_true(snapshot.progress <= 1.0)
    if motion.is_hold_only() {
      assert_true(snapshot.held_ms > 0)
    } else {
      assert_true(snapshot.reps >= 1)
    }
  }
}
