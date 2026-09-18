// MoveMentor 命令行自检工具
//
// 它不是演示界面，而是「可复现的验收工具」：不依赖摄像头、不依赖网络，
// 在任何一台装了 MoonBit 的机器上都能跑出同样的输出，用来证明
//   规则表能解析 → 翻译能命中 → 约束校验能拦住坏映射 → 计数器能数对次数
// 这一整条链路是通的。
//
// 用法：
//   moon run cmd/main                  全量自检
//   moon run cmd/main -- dsl           打印内置规则表 DSL
//   moon run cmd/main -- metrics       打印每个动作的指标扫描（调阈值时看这张表）
//   moon run cmd/main -- translate <动作> <人群>
//   moon run cmd/main -- demo <动作> <人群> [秒数]

///|
fn main {
  let args = @env.args()
  let program = @engine.builtin_program()
  let command = if args.length() > 2 { args[2] } else { "" }
  if command == "dsl" {
    println(@engine.builtin_source())
  } else if command == "metrics" {
    dump_metrics(program)
  } else if command == "translate" {
    let motion = if args.length() > 3 { args[3] } else { "jumping_jack" }
    let audience = if args.length() > 4 { args[4] } else { "elderly_knee_pain" }
    print_translation(program, motion, audience)
  } else if command == "demo" {
    let motion = if args.length() > 3 { args[3] } else { "jumping_jack" }
    let audience = if args.length() > 4 { args[4] } else { "elderly_knee_pain" }
    let seconds = if args.length() > 5 { seconds_or(args[5], 12) } else { 12 }
    run_demo(program, motion, audience, seconds)
  } else {
    full_audit(program)
  }
}

///|
fn seconds_or(text : String, fallback : Int) -> Int {
  match @engine.parse_double_opt(text) {
    Some(value) => value.to_int()
    None => fallback
  }
}

///|
/// 全量自检：规则表统计 + 每条映射的校验 + 基线恒等 + 离线演示 + 反向翻译。
fn full_audit(program : @engine.DslProgram) -> Unit {
  println("== MoveMentor 引擎自检 ==")
  println(
    "动作 \{program.motions.length()} 个｜人群 \{program.audiences.length()} 个｜翻译规则 \{program.variants.length()} 条",
  )
  if program.issues.length() > 0 {
    println("规则表存在问题 \{program.issues.length()} 处：")
    for issue in program.issues {
      println("  第 \{issue.line} 行：\{issue.message}")
    }
    return
  }
  println("规则表解析：通过，无诊断信息")
  println("")
  println("-- 每一条翻译规则的约束校验 --")
  for rule in program.variants {
    match
      (
        program.motion(rule.source),
        program.audience(rule.audience),
        program.motion(rule.target),
      ) {
      (Some(source), Some(audience), Some(target)) => {
        let violations = @engine.validate(target, audience)
        if violations.length() == 0 {
          println(
            "  ✓ \{source.display_name} + \{audience.display_name} → \{target.display_name}",
          )
        } else {
          println(
            "  ✗ \{source.display_name} + \{audience.display_name} → \{target.display_name}",
          )
          for v in violations {
            println("      \{v}")
          }
        }
      }
      _ =>
        println(
          "  ✗ 规则引用了不存在的声明：\{rule.source} / \{rule.audience} / \{rule.target}",
        )
    }
  }
  println("")
  println("-- 基线人群（general）应当是恒等映射 --")
  for motion in program.motions {
    match @engine.translate(program, motion.id, "general") {
      @engine.Translated(t) =>
        println("  ✓ \{motion.id}：\{t.kind} → \{t.plan.id}")
      @engine.Substituted(t) =>
        println("  ✗ \{motion.id}：被意外替换为 \{t.plan.id}")
      @engine.Unsupported(msg) => println("  ✗ \{motion.id}：\{msg}")
    }
  }
  println("")
  println(
    "-- 离线演示（合成姿态源，每个受限人群跑一个动作）--",
  )
  for rule in program.variants {
    run_demo(program, rule.source, rule.audience, 12)
  }
  println("")
  println("-- 反向翻译 --")
  for motion in program.motions {
    let sources = @engine.reverse_sources(program, motion.id)
    if sources.length() > 0 {
      let names = StringBuilder()
      for source in sources {
        if names.to_string().length() > 0 {
          names.write_string("、")
        }
        names.write_string(source.display_name)
      }
      println("  \{motion.display_name} ← \{names.to_string()}")
    }
  }
  println("")
  println(
    "自检结束。以上全部为确定性计算，重复运行结果一致。",
  )
}

///|
/// 指标扫描：把某动作声明的每个指标在 s = 0 → 1 上的读数打出来，
/// 旁边标注 DSL 里声明的阈值。调阈值时看这张表。
fn dump_metrics(program : @engine.DslProgram) -> Unit {
  let steps : Array[Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
  println("每个动作的指标扫描（s：0 = 起始位，1 = 做到位）")
  for motion in program.motions {
    let archetype = @engine.archetype_of(motion)
    println("")
    println(
      "\{motion.id}（\{motion.display_name}）｜合成原型 \{archetype.token()}",
    )
    for metric in motion.required_metrics() {
      let line = StringBuilder()
      line.write_string("  \{metric}：")
      for s in steps {
        let frame = @engine.synth_params(archetype, motion, s).to_frame()
        match @engine.metric_value(metric, frame) {
          Some(v) => line.write_string(" \{v} ")
          None => line.write_string(" n/a ")
        }
      }
      line.write_string("｜阈值")
      for phase in motion.phases {
        for target in phase.targets {
          if target.metric == metric {
            line.write_string(" (\{phase.id}) \{target.to_text()}")
          }
        }
      }
      println(line.to_string())
    }
  }
}

///|
fn print_translation(
  program : @engine.DslProgram,
  motion_id : String,
  audience_id : String,
) -> Unit {
  match @engine.translate(program, motion_id, audience_id) {
    @engine.Translated(t) => {
      println("命中规则表：\{t.headline()}")
      println("说明：\{t.reason}")
      for line in t.checks {
        println("  校验：\{line}")
      }
    }
    @engine.Substituted(t) => {
      println("未命中专属变式，已替换：\{t.headline()}")
      println("说明：\{t.reason}")
    }
    @engine.Unsupported(msg) => println("无可执行方案：\{msg}")
  }
}

///|
/// 用合成姿态跑一遍完整演示：翻译 → 计数器 → 指导语。
fn run_demo(
  program : @engine.DslProgram,
  motion_id : String,
  audience_id : String,
  seconds : Int,
) -> Unit {
  match @engine.translate(program, motion_id, audience_id) {
    @engine.Translated(t) => demo_body(t, seconds)
    @engine.Substituted(t) => demo_body(t, seconds)
    @engine.Unsupported(msg) =>
      println("  ✗ \{audience_id} + \{motion_id}：\{msg}")
  }
}

///|
fn demo_body(translation : @engine.Translation, seconds : Int) -> Unit {
  let plan = translation.plan
  println("")
  println("▶ \{translation.headline()}")
  println("  来源：\{translation.kind}｜\{translation.reason}")
  let counter = @engine.RepCounter::new(plan)
  let fps = 30
  let frame_ms = 1000 / fps
  let total = seconds * fps
  for i in 0..<total {
    let now = i * frame_ms
    let frame = @engine.synth_frame(plan, now)
    let snapshot = counter.update(frame, now)
    match snapshot.event {
      @engine.CompletedRep(n) =>
        println("    · 完成第 \{n} 次（相位 \{snapshot.phase_id}）")
      @engine.HoldTick(s) => println("    · 保持 \{s} 秒")
      @engine.EnteredPhase(_) => ()
      @engine.LowConfidence => ()
      @engine.Idle => ()
    }
  }
  if plan.is_hold_only() {
    println(
      "  结果：保持 \{counter.held_ms / 1000} 秒，目标 \{plan.hold_only_ms / 1000} 秒",
    )
  } else {
    println("  结果：\{counter.reps} 次完成（时长 \{seconds} 秒）")
  }
  println("  指导语：")
  for line in @engine.guidance_script(translation, seconds, counter.reps) {
    println("    「\{line}」")
  }
}
