// 翻译引擎与校验规则的白盒测试。
//
// 最重要的一条在最后：**内置规则表里的每一条映射都必须通过校验**。
// 这条断言把「规则表」从一个数据文件变成了有回归保护的东西——
// 以后往表里加一条错误的映射（比如让膝痛人群做深蹲到底），
// `moon test` 会立刻失败。

///|
test "validate: 同向约束不冲突" {
  let at_least = Constraint::new("ankle_span", AtLeast, 1.6)
  let at_most = Constraint::new("knee_left", AtMost, 105.0)
  assert_true(!conflicts(at_least, Constraint::new("ankle_span", AtLeast, 0.5)))
  assert_true(!conflicts(at_most, Constraint::new("knee_left", AtMost, 120.0)))
}

///|
test "validate: 要求高于上限 / 低于下限才算冲突" {
  let target = Constraint::new("knee_left", AtLeast, 120.0)
  let ceiling = Constraint::new("knee_left", AtMost, 105.0)
  assert_true(conflicts(target, ceiling))
  assert_true(!conflicts(Constraint::new("knee_left", AtLeast, 100.0), ceiling))
  let floor = Constraint::new("knee_left", AtLeast, 90.0)
  assert_true(conflicts(Constraint::new("knee_left", AtMost, 80.0), floor))
  assert_true(!conflicts(Constraint::new("knee_left", AtMost, 95.0), floor))
}

///|
test "validate: 载荷等级能拦住坏映射" {
  let program = builtin_program()
  let knee_pain = builtin_audience(program, "elderly_knee_pain")
  let jumping_jack = builtin_motion(program, "jumping_jack")
  let violations = validate(jumping_jack, knee_pain)
  // 开合跳的 impact=high 超出该人群的 impact=none
  assert_true(violations.length() >= 1)
  let deep_squat = builtin_motion(program, "squat")
  let squat_violations = validate(deep_squat, knee_pain)
  // 深蹲的 knee=high 超出该人群的 knee=low
  assert_true(squat_violations.length() >= 1)
}

///|
test "validate: 正确的变式必须通过" {
  let program = builtin_program()
  let knee_pain = builtin_audience(program, "elderly_knee_pain")
  let seated = builtin_motion(program, "seated_leg_lift")
  let chair = builtin_motion(program, "chair_squat")
  let wall = builtin_motion(program, "wall_body_hold")
  assert_eq(validate(seated, knee_pain).length(), 0)
  assert_eq(validate(chair, knee_pain).length(), 0)
  assert_eq(validate(wall, knee_pain).length(), 0)
}

///|
test "validate: 未声明的载荷轴不做限制" {
  let program = builtin_program()
  let office = builtin_audience(program, "office_sedentary")
  let chair = builtin_motion(program, "chair_squat")
  // chair_squat 声明了 hip=medium，而办公人群没有声明 hip 的上限
  assert_eq(validate(chair, office).length(), 0)
}

///|
test "translate: 基线人群是恒等映射" {
  let program = builtin_program()
  for motion in program.motions {
    match translate(program, motion.id, "general") {
      Translated(t) => {
        assert_eq(t.kind, "identity")
        assert_eq(t.plan.id, motion.id)
      }
      Substituted(_) => fail("\{motion.id} 在基线人群下不应被替换")
      Unsupported(msg) =>
        fail("\{motion.id} 在基线人群下不可用：\{msg}")
    }
  }
}

///|
test "translate: 膝痛人群下开合跳被翻译成坐姿抬腿" {
  let program = builtin_program()
  match translate(program, "jumping_jack", "elderly_knee_pain") {
    Translated(t) => {
      assert_eq(t.kind, "translated")
      assert_eq(t.plan.id, "seated_leg_lift")
      assert_eq(t.requested_name, "开合跳")
      assert_eq(t.plan.display_name, "坐姿抬腿（单腿）")
      assert_true(t.reason.length() > 0)
      assert_true(t.checks.length() > 0)
      assert_true(t.headline().has_prefix("开合跳 → 坐姿抬腿"))
    }
    Substituted(_) => fail("应当命中专属变式而不是替换")
    Unsupported(msg) => fail("应当命中专属变式：\{msg}")
  }
}

///|
test "translate: 未知动作与未知人群返回 Unsupported" {
  let program = builtin_program()
  assert_true(translate(program, "moon_walk", "general") is Unsupported(_))
  assert_true(translate(program, "jumping_jack", "astronaut") is Unsupported(_))
}

///|
test "translate: 没有专属变式时替换为同族动作，且替换结果必须过校验" {
  let program = builtin_program()
  let audience = builtin_audience(program, "elderly_knee_pain")
  match translate(program, "low_impact_step", "elderly_knee_pain") {
    Substituted(t) => {
      assert_eq(t.kind, "substituted")
      assert_true(t.plan.id != "low_impact_step")
      // 替换不能是「随便找一个」：结果必须真的落在能力边界内
      assert_eq(validate(t.plan, audience).length(), 0)
    }
    Translated(t) =>
      fail(
        "low_impact_step 没有专属变式，不该命中规则表：\{t.plan.id}",
      )
    Unsupported(msg) => fail("应当给出同族替代：\{msg}")
  }
}

///|
test "translate: 替换结果确定性（同一输入永远同一输出）" {
  let program = builtin_program()
  let first = translate(program, "low_impact_step", "elderly_knee_pain")
  let second = translate(program, "low_impact_step", "elderly_knee_pain")
  match (first, second) {
    (Substituted(a), Substituted(b)) => assert_eq(a.plan.id, b.plan.id)
    _ => fail("两次调用的结果形态不一致")
  }
}

///|
test "reverse: 反向翻译能一对多" {
  let program = builtin_program()
  let sources = reverse_sources(program, "seated_leg_lift")
  let ids : Array[String] = []
  for source in sources {
    ids.push(source.id)
  }
  assert_eq(ids.length(), 2)
  assert_eq(ids[0], "jumping_jack")
  assert_eq(ids[1], "squat")
  // 源动作本身不是任何变式
  assert_eq(reverse_sources(program, "jumping_jack").length(), 0)
}

///|
test "check: 校验证据必须引用真实比较过的量" {
  let program = builtin_program()
  match translate(program, "jumping_jack", "elderly_knee_pain") {
    Translated(t) => {
      let mut mentions_impact = false
      for line in t.checks {
        if line.has_prefix("载荷 impact") {
          mentions_impact = true
        }
      }
      assert_true(mentions_impact)
    }
    _ => fail("应当翻译成功")
  }
}

///|
test "内置规则表回归：每一条映射都必须通过约束校验" {
  let program = builtin_program()
  for rule in program.variants {
    let audience = builtin_audience(program, rule.audience)
    let target = builtin_motion(program, rule.target)
    let violations = validate(target, audience)
    if violations.length() > 0 {
      fail(
        "规则 `\{rule.source} × \{rule.audience} -> \{rule.target}` 不自洽：\{violations[0]}",
      )
    }
  }
}

///|
test "内置规则表回归：每个源动作在每个受限人群下都能拿到方案" {
  let program = builtin_program()
  let audiences = ["elderly_knee_pain", "wheelchair", "office_sedentary"]
  for motion in program.motions {
    for audience in audiences {
      let outcome = translate(program, motion.id, audience)
      match outcome {
        Translated(t) =>
          assert_eq(
            validate(t.plan, builtin_audience(program, audience)).length(),
            0,
          )
        Substituted(t) =>
          assert_eq(
            validate(t.plan, builtin_audience(program, audience)).length(),
            0,
          )
        Unsupported(msg) =>
          fail("\{motion.id} × \{audience} 无方案：\{msg}")
      }
    }
  }
}
