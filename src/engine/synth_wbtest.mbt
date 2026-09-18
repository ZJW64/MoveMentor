// 合成姿态源的白盒测试。
//
// 合成源的地位很特殊：它既是「离线演示」的数据来源，又是端到端测试的输入。
// 因此它必须满足一条硬约束——**动作 DSL 里声明的每一个相位目标，
// 都必须在某一段合成轨迹上被真正满足**。否则测试会变成
// 「合成数据自己过不了自己的阈值」，整个离线演示也会是假的。

///|
test "synth: 波形两端有平台" {
  assert_true(almost_equal(trapezoid(0.0), 0.0, 0.0001))
  assert_true(almost_equal(trapezoid(0.10), 0.5, 0.0001))
  assert_true(almost_equal(trapezoid(0.20), 1.0, 0.0001))
  assert_true(almost_equal(trapezoid(0.40), 1.0, 0.0001))
  assert_true(almost_equal(trapezoid(0.60), 0.5, 0.0001))
  assert_true(almost_equal(trapezoid(0.70), 0.0, 0.0001))
  assert_true(almost_equal(trapezoid(0.95), 0.0, 0.0001))
}

///|
test "synth: 原型推断" {
  let program = builtin_program()
  let expected : Array[(String, Archetype)] = [
    ("jumping_jack", StandingBilateral),
    ("squat", Squat),
    ("plank", LeanHold),
    ("low_impact_step", StandingBilateral),
    ("chair_squat", Squat),
    ("wall_body_hold", LeanHold),
    ("seated_leg_lift", SeatedLegLift),
    ("seated_arm_raise", SeatedArmRaise),
    ("seated_torso_brace", LeanHold),
  ]
  for (id, archetype) in expected {
    assert_eq(archetype_of(builtin_motion(program, id)), archetype)
  }
}

///|
test "synth: 周期由保持时长推导且不小于 1.6 秒" {
  let program = builtin_program()
  // 开合跳：2 × (180 + 180 + 400) = 1520 → 抬高到 1600
  assert_eq(synth_period_ms(builtin_motion(program, "jumping_jack")), 1600)
  // 扶椅浅蹲：2 × (250 + 250 + 400) = 1800
  assert_eq(synth_period_ms(builtin_motion(program, "chair_squat")), 1800)
  // 等长动作固定 2000
  assert_eq(synth_period_ms(builtin_motion(program, "wall_body_hold")), 2000)
}

///|
test "synth: 同一个时间点永远生成同一帧" {
  let motion = builtin_motion(builtin_program(), "seated_arm_raise")
  let a = synth_frame(motion, 1234)
  let b = synth_frame(motion, 1234)
  for i in 0..<(POSE_POINT_COUNT * POSE_STRIDE) {
    assert_eq(a.points[i], b.points[i])
  }
}

///|
test "synth: 单腿动作只驱动被引用的那条腿" {
  let program = builtin_program()
  let motion = builtin_motion(program, "seated_leg_lift")
  // DSL 只引用了 shin_drop_right
  assert_true(has_target(motion, "shin_drop_right"))
  assert_true(!has_target(motion, "shin_drop_left"))
  let params = synth_params(SeatedLegLift, motion, 1.0)
  assert_true(!params.drive_left)
  assert_true(params.drive_right)
  // 未被驱动的一侧停在坐姿静息位
  let frame = params.to_frame()
  assert_true(
    almost_equal(metric_value("shin_drop_left", frame).unwrap(), 2.0, 0.001),
  )
  assert_true(metric_value("shin_drop_right", frame).unwrap() < 0.7)
}

///|
test "synth: 阈值推断的辅助函数" {
  let motion = builtin_motion(builtin_program(), "chair_squat")
  assert_true(
    almost_equal(
      highest_at_least(motion, "hip_height_ratio").unwrap(),
      0.792,
      0.0001,
    ),
  )
  assert_true(
    almost_equal(
      lowest_at_most(motion, "hip_height_ratio").unwrap(),
      0.775,
      0.0001,
    ),
  )
  assert_true(highest_at_least(motion, "ankle_span") is None)
  assert_true(lowest_at_most(motion, "ankle_span") is None)
}

///|
test "synth: 髋高比反解与正向计算互逆" {
  let torso = 0.12
  let ankle_y = 0.90
  for i in 0..<10 {
    let ratio = 0.70 + i.to_double() * 0.02
    let hip_y = hip_y_for_ratio(ratio, ankle_y, torso)
    let frame = PoseFrame::empty()
    let center = 0.5
    frame.set(
      LeftShoulder,
      Landmark::new(center - 0.06, hip_y - torso, 0.0, 1.0),
    )
    frame.set(
      RightShoulder,
      Landmark::new(center + 0.06, hip_y - torso, 0.0, 1.0),
    )
    frame.set(LeftHip, Landmark::new(center - 0.035, hip_y, 0.0, 1.0))
    frame.set(RightHip, Landmark::new(center + 0.035, hip_y, 0.0, 1.0))
    frame.set(LeftAnkle, Landmark::new(center - 0.03, ankle_y, 0.0, 1.0))
    frame.set(RightAnkle, Landmark::new(center + 0.03, ankle_y, 0.0, 1.0))
    assert_true(
      almost_equal(
        metric_value("hip_height_ratio", frame).unwrap(),
        ratio,
        0.002,
      ),
    )
  }
}

///|
test "synth: 每个动作的每个相位，都必须存在能同时满足其全部目标的时刻" {
  let program = builtin_program()
  for motion in program.motions {
    let archetype = archetype_of(motion)
    for phase in motion.phases {
      let mut satisfiable = false
      for i in 0..<=40 {
        let s = i.to_double() / 40.0
        let frame = synth_params(archetype, motion, s).to_frame()
        if phase_satisfied(phase, frame, motion.hysteresis, false) {
          satisfiable = true
        }
      }
      if !satisfiable {
        fail(
          "动作 \{motion.id} 的相位 \{phase.id} 在合成轨迹上永远无法满足",
        )
      }
    }
  }
}

///|
test "synth: 每个重复动作的相位推进在合成轨迹上都能真正发生" {
  let program = builtin_program()
  for motion in program.motions {
    if !motion.is_hold_only() {
      let snapshot = simulate(motion, 30)
      if snapshot.reps < 3 {
        fail(
          "动作 \{motion.id} 在 30 秒合成轨迹上只完成 \{snapshot.reps} 次，阈值或波形不匹配",
        )
      }
    }
  }
}
