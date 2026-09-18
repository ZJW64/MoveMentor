// DSL 解析器的白盒测试。
//
// 解析器是这套引擎里唯一「会读入外部文本」的地方，也是最容易被写坏的地方。
// 测试分两层：
//   1. 词法/单项解析（数字、约束、行拆分）——边界值密集；
//   2. 整份程序的语义检查（重名、悬空引用、翻译链）——错误必须被收集而不是崩溃。

///|
test "parse_double: 只接受十进制字面量" {
  assert_eq(parse_double_opt("1.8"), Some(1.8))
  assert_eq(parse_double_opt("-2"), Some(-2.0))
  assert_eq(parse_double_opt("+3.25"), Some(3.25))
  assert_eq(parse_double_opt("0"), Some(0.0))
  assert_eq(parse_double_opt(""), None)
  assert_eq(parse_double_opt("."), None)
  assert_eq(parse_double_opt("1.2.3"), None)
  assert_eq(parse_double_opt("1e3"), None)
  assert_eq(parse_double_opt("abc"), None)
  assert_eq(parse_double_opt("1.8cm"), None)
}

///|
test "parse_constraint: 两种方向" {
  let at_most = parse_constraint("knee_left<=105").unwrap()
  assert_eq(at_most.metric, "knee_left")
  assert_eq(at_most.cmp, AtMost)
  assert_eq(at_most.value, 105.0)
  let at_least = parse_constraint("ankle_span>=1.60").unwrap()
  assert_eq(at_least.cmp, AtLeast)
  assert_eq(at_least.value, 1.6)
  assert_true(parse_constraint("knee_left<105") is None)
  assert_true(parse_constraint("<=105") is None)
  assert_true(parse_constraint("knee_left<=") is None)
}

///|
test "constraint: 判定与滞回" {
  let threshold = Constraint::new("ankle_span", AtLeast, 1.6)
  assert_true(threshold.satisfied_by(1.6))
  assert_true(threshold.satisfied_by(2.0))
  assert_true(!threshold.satisfied_by(1.59))
  // 滞回：进入要求 1.6，维持放宽到 1.4
  assert_true(threshold.satisfied_with_hysteresis(1.45, 0.2))
  assert_true(!threshold.satisfied_with_hysteresis(1.35, 0.2))
  let ceiling = Constraint::new("knee_left", AtMost, 105.0)
  assert_true(ceiling.satisfied_by(105.0))
  assert_true(!ceiling.satisfied_by(105.1))
  assert_true(ceiling.satisfied_with_hysteresis(107.0, 3.0))
  assert_true(!ceiling.satisfied_with_hysteresis(108.5, 3.0))
  assert_eq(threshold.to_text(), "ankle_span>=1.6")
}

///|
test "level: 序数与字面量" {
  assert_eq(Level::from_token("none"), Some(NoLoad))
  assert_eq(Level::from_token("high"), Some(High))
  assert_eq(Level::from_token("extreme"), None)
  assert_true(NoLoad.rank() < Low.rank())
  assert_true(Low.rank() < Medium.rank())
  assert_true(Medium.rank() < High.rank())
  assert_eq(High.token(), "high")
  assert_eq(NoLoad.label(), "无")
}

///|
test "dsl: 最小程序能解析" {
  let source = "motion demo\nname 演示动作\nphase on hold=200 hip_height_ratio<=0.7\nphase off hold=200 hip_height_ratio>=0.8\ncycle on off\n"
  let program = parse_program(source)
  assert_eq(program.issues.length(), 0)
  assert_eq(program.motions.length(), 1)
  let motion = program.motions[0]
  assert_eq(motion.id, "demo")
  assert_eq(motion.display_name, "演示动作")
  assert_eq(motion.phases.length(), 2)
  assert_eq(motion.cycle_phases().length(), 2)
  assert_eq(motion.required_metrics().length(), 1)
}

///|
test "dsl: 省略 cycle 时按声明顺序" {
  let source = "motion demo\nname 演示\nphase a hold=100 hip_height_ratio<=0.7\nphase b hold=100 hip_height_ratio>=0.8\n"
  let program = parse_program(source)
  assert_eq(program.issues.length(), 0)
  let phases = program.motions[0].cycle_phases()
  assert_eq(phases.length(), 2)
  assert_eq(phases[0].id, "a")
  assert_eq(phases[1].id, "b")
}

///|
test "dsl: 未闭合声明头与注释行" {
  let source = "# 注释\n\nmotion demo\nname 演示\nphase a hold=100 hip_height_ratio<=0.7\n"
  let program = parse_program(source)
  assert_eq(program.issues.length(), 0)
  assert_eq(program.motions.length(), 1)
  // 声明体出现在任何声明头之前：必须报错而不是静默忽略
  let broken = parse_program("name 野生字段\nmotion demo\nname 演示\n")
  assert_eq(broken.issues.length(), 2)
  assert_true(broken.issues[0].message.has_prefix("缺少 motion"))
  assert_eq(broken.motions.length(), 1)
}

///|
test "dsl: 未知指标必须被拦下" {
  let source = "motion demo\nname 演示\nphase a hold=100 knee_flexion<=90\n"
  let program = parse_program(source)
  assert_eq(program.issues.length(), 1)
  assert_true(program.issues[0].message.has_prefix("未知指标"))
  assert_eq(program.issues[0].line, 3)
}

///|
test "dsl: 未知字段、未知载荷等级、未知视图都要报错" {
  let source = "motion demo\nname 演示\nview top\nload impact=extreme\nspeed 3\nphase a hold=100 hip_height_ratio<=0.7\n"
  let program = parse_program(source)
  // view top / load impact=extreme / speed 3 各报一条
  assert_eq(program.issues.length(), 3)
}

///|
test "dsl: 缺 name、缺相位、cycle 引用不存在的相位" {
  let missing_name = parse_program(
    "motion demo\nphase a hold=100 hip_height_ratio<=0.7\n",
  )
  assert_eq(missing_name.issues.length(), 1)
  let no_phase = parse_program("motion demo\nname 演示\n")
  assert_eq(no_phase.issues.length(), 1)
  let bad_cycle = parse_program(
    "motion demo\nname 演示\nphase a hold=100 hip_height_ratio<=0.7\ncycle a zz\n",
  )
  assert_eq(bad_cycle.issues.length(), 1)
  assert_true(
    bad_cycle.issues[0].message.has_prefix("cycle 引用了不存在"),
  )
}

///|
test "dsl: 重名与悬空引用" {
  let duplicate = parse_program(
    "motion demo\nname 甲\nphase a hold=100 hip_height_ratio<=0.7\nmotion demo\nname 乙\nphase a hold=100 hip_height_ratio<=0.7\n",
  )
  assert_eq(duplicate.motions.length(), 1)
  assert_eq(duplicate.issues.length(), 1)
  assert_true(duplicate.issues[0].message.has_prefix("动作 id 重复"))
}

///|
test "dsl: 翻译规则指向不存在的东西" {
  let source = "motion demo\nname 演示\nphase a hold=100 hip_height_ratio<=0.7\naudience old\nname 人群\nvariant demo old -> nowhere\nvariant ghost old -> demo\n"
  let program = parse_program(source)
  let mut missing_target = false
  let mut missing_source = false
  for issue in program.issues {
    if issue.message.has_prefix("翻译规则引用了不存在的变式动作") {
      missing_target = true
    }
    if issue.message.has_prefix("翻译规则引用了不存在的源动作") {
      missing_source = true
    }
  }
  assert_true(missing_target)
  assert_true(missing_source)
}

///|
test "dsl: 不支持翻译链" {
  let source = "motion a\nname 甲\nphase p hold=100 hip_height_ratio<=0.7\nmotion b\nname 乙\nphase p hold=100 hip_height_ratio<=0.7\nmotion c\nname 丙\nphase p hold=100 hip_height_ratio<=0.7\naudience u\nname 人群\nvariant a u -> b\nvariant b u -> c\n"
  let program = parse_program(source)
  let mut found = false
  for issue in program.issues {
    if issue.message.has_prefix("翻译链不被支持") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "dsl: variant 缺少箭头" {
  let source = "motion a\nname 甲\nphase p hold=100 hip_height_ratio<=0.7\naudience u\nname 人群\nvariant a u\n"
  let program = parse_program(source)
  assert_eq(program.issues.length(), 1)
  assert_true(program.issues[0].message.has_prefix("variant 缺少"))
}

///|
test "catalog: 内置规则表必须零诊断" {
  let program = builtin_program()
  for issue in program.issues {
    fail("内置规则表第 \{issue.line} 行有问题：\{issue.message}")
  }
  assert_eq(program.motions.length(), 9)
  assert_eq(program.audiences.length(), 4)
  assert_eq(program.variants.length(), 9)
}

///|
test "catalog: 每个动作都写了 name / cue，且能被翻译器使用" {
  let program = builtin_program()
  for motion in program.motions {
    assert_true(motion.display_name.length() > 0)
    assert_true(motion.cues.length() > 0)
    assert_true(motion.view == "front" || motion.view == "side")
    assert_true(motion.is_hold_only() || motion.cycle_phases().length() > 0)
  }
  for audience in program.audiences {
    assert_true(audience.display_name.length() > 0)
    assert_true(audience.notes.length() > 0)
  }
}

///|
test "catalog: 三源动作在三种受限人群下都有专属变式" {
  let program = builtin_program()
  let sources = ["jumping_jack", "squat", "plank"]
  let audiences = ["elderly_knee_pain", "wheelchair", "office_sedentary"]
  for source in sources {
    for audience in audiences {
      assert_true(program.variant_for(source, audience) is Some(_))
    }
  }
}
