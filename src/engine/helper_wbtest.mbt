// 白盒测试的公共辅助。
//
// 这里的 helper 刻意保持极简：测试自己要足够直白，否则测试本身就成了
// 需要被测试的东西。所有「构造一帧姿态」的逻辑都只有这一个入口。

///|
/// 用手写的关键点位置拼一帧姿态。未列出的关键点停在坐标原点、visibility = 1。
fn frame_of(entries : Array[(Joint, Double, Double)]) -> PoseFrame {
  let frame = PoseFrame::empty()
  for (joint, x, y) in entries {
    frame.set(joint, Landmark::new(x, y, 0.0, 1.0))
  }
  frame
}

///|
/// 标准站姿骨架，数值与 `SkeletonParams::standing()` 一致。
/// 手上没有摄像头时，这就是「一帧正常的站立姿态」。
fn standing_frame() -> PoseFrame {
  frame_of([
    (LeftShoulder, 0.44, 0.30),
    (RightShoulder, 0.56, 0.30),
    (LeftElbow, 0.42, 0.42),
    (RightElbow, 0.58, 0.42),
    (LeftWrist, 0.42, 0.54),
    (RightWrist, 0.58, 0.54),
    (LeftHip, 0.465, 0.42),
    (RightHip, 0.535, 0.42),
    (LeftKnee, 0.47, 0.66),
    (RightKnee, 0.53, 0.66),
    (LeftAnkle, 0.47, 0.90),
    (RightAnkle, 0.53, 0.90),
  ])
}

///|
/// 从内置规则表里取一个动作，取不到就直接让测试失败。
fn builtin_motion(program : DslProgram, id : String) -> MotionSpec raise {
  match program.motion(id) {
    Some(m) => m
    None => fail("内置规则表里缺少动作 \{id}")
  }
}

///|
/// 从内置规则表里取一个人群。
fn builtin_audience(program : DslProgram, id : String) -> AudienceProfile raise {
  match program.audience(id) {
    Some(a) => a
    None => fail("内置规则表里缺少人群 \{id}")
  }
}

///|
/// 用合成姿态把某个动作跑 `seconds` 秒，返回最后一次快照。
fn simulate(plan : MotionSpec, seconds : Int) -> CounterSnapshot {
  let counter = RepCounter::new(plan)
  let fps = 30
  let frame_ms = 1000 / fps
  let mut last = counter.update(synth_frame(plan, 0), 0)
  for i in 0..<(seconds * fps) {
    let now = i * frame_ms
    last = counter.update(synth_frame(plan, now), now)
  }
  last
}
