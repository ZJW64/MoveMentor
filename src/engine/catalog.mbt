// MoveMentor 核心引擎 · 内置规则表
//
// 规则表用 DSL 写在一段多行字符串里，而不是硬编码成结构体字面量。三个理由：
//   1. 它读起来就是一张「动作 → 人群 → 变式」的表格，评审和医生都能审；
//   2. 解析过程本身有测试（见 dsl_wbtest.mbt），规则表坏了会当场报错；
//   3. 改数据不需要碰引擎代码，这是「引擎 + 应用」这个边界能成立的前提。
//
// 措辞说明：全表统一使用「低冲击变式」「降低关节负荷」这类表述，
// 不使用「安全」「适合病人」「医疗有效」。见 docs/06-安全边界与免责声明.md。
//
// 载荷等级：none(0) < low(1) < medium(2) < high(3)。
// 校验规则只比较「动作要求的等级」与「人群声明的上限」，
// 没有声明上限的载荷轴不参与校验（表示该人群对此没有额外限制）。

///|
/// 内置动作与人群规则表的 DSL 源文本。
pub fn builtin_source() -> String {
  (
    #|# MoveMentor 内置规则表 v1
    #|# 三个源动作（开合跳 / 深蹲 / 平板支撑）x 三种受限人群（膝痛、轮椅、久坐）
    #|
    #|motion jumping_jack
    #|name 开合跳
    #|view front
    #|tag cardio
    #|tag impact
    #|tag bilateral
    #|load impact=high
    #|load knee=medium
    #|load balance=medium
    #|phase open hold=180 ankle_span>=1.60 wrist_above_shoulder_left>=1.00 wrist_above_shoulder_right>=1.00
    #|phase close hold=180 ankle_span<=0.60
    #|cycle open close
    #|min_rep_ms 400
    #|hysteresis 0.20
    #|cue 双脚并拢站好，双手自然垂在身体两侧
    #|cue 起跳时双脚向两侧分开，同时双臂向两侧举过头顶
    #|cue 落地时用屈膝缓冲，保持躯干直立，不要含胸
    #|
    #|motion squat
    #|name 徒手深蹲
    #|view front
    #|tag strength
    #|tag standing
    #|load impact=low
    #|load knee=high
    #|load hip=high
    #|load balance=medium
    #|phase down hold=200 hip_height_ratio<=0.760
    #|phase up hold=200 hip_height_ratio>=0.790
    #|cycle down up
    #|min_rep_ms 700
    #|hysteresis 0.010
    #|cue 双脚与肩同宽，脚尖朝前
    #|cue 髋部向后向下坐，膝盖尽量不超过脚尖
    #|cue 起身时用大腿发力，不要用腰部代偿
    #|
    #|motion plank
    #|name 平板支撑
    #|view side
    #|tag core
    #|tag floor
    #|tag hold
    #|load impact=none
    #|load spine=high
    #|load shoulder=medium
    #|hold_only_ms 30000
    #|phase brace hold=500 trunk_lean>=70
    #|cue 肘部支撑，前臂贴地，双脚与髋同宽
    #|cue 从头到脚跟保持一条直线，收紧腹部和臀部
    #|cue 不要塌腰，也不要耸肩
    #|
    #|motion low_impact_step
    #|name 无跳跃开合步
    #|view front
    #|tag standing
    #|tag low_impact
    #|tag cardio
    #|load impact=none
    #|load knee=low
    #|load balance=medium
    #|phase open hold=200 ankle_span>=1.30 wrist_above_shoulder_left>=0.30 wrist_above_shoulder_right>=0.30
    #|phase close hold=200 ankle_span<=0.65
    #|cycle open close
    #|min_rep_ms 400
    #|hysteresis 0.20
    #|cue 站直，双脚交替向两侧点地，不跳跃、不腾空
    #|cue 手臂随节拍在身体两侧打开，抬到与肩同高即可
    #|cue 落地始终有一脚踩实，重心保持在两脚之间
    #|
    #|motion chair_squat
    #|name 扶椅浅蹲
    #|view front
    #|tag standing
    #|tag low_impact
    #|tag supported
    #|load impact=none
    #|load knee=low
    #|load hip=medium
    #|load balance=low
    #|load spine=low
    #|phase down hold=250 hip_height_ratio<=0.775
    #|phase up hold=250 hip_height_ratio>=0.792
    #|cycle down up
    #|min_rep_ms 800
    #|hysteresis 0.008
    #|cue 站在椅背后方，双手扶住椅背，双脚与肩同宽
    #|cue 髋部向后下方坐，蹲到一半就停，不必蹲到底
    #|cue 起身时靠大腿和臀部发力，全程不要憋气
    #|
    #|motion wall_body_hold
    #|name 靠墙直立（等长）
    #|view side
    #|tag standing
    #|tag low_impact
    #|tag supported
    #|tag hold
    #|load impact=none
    #|load balance=low
    #|load knee=low
    #|load spine=low
    #|hold_only_ms 20000
    #|phase brace hold=500 trunk_lean<=5 hip_height_ratio>=0.75
    #|cue 后脑、上背和髋部轻贴墙面，双脚离墙约一脚掌
    #|cue 收紧腹部，把腰与墙之间的空隙收小，保持自然呼吸
    #|cue 感觉腿累可以随时靠墙休息
    #|
    #|motion seated_leg_lift
    #|name 坐姿抬腿（单腿）
    #|view side
    #|tag seated
    #|tag low_impact
    #|tag lower_limb
    #|load impact=none
    #|load knee=low
    #|load hip=low
    #|load spine=low
    #|phase lift hold=250 shin_drop_right<=0.70
    #|phase lower hold=250 shin_drop_right>=1.80
    #|cycle lift lower
    #|min_rep_ms 600
    #|hysteresis 0.15
    #|cue 坐稳在椅子上，双脚平放地面，背部离开椅背
    #|cue 缓慢抬起右小腿，抬到膝盖接近水平，停一下再慢慢放下
    #|cue 全程保持躯干稳定，不要用身体后仰来借力；做完一组换左腿
    #|
    #|motion seated_arm_raise
    #|name 坐姿双臂上举
    #|view front
    #|tag seated
    #|tag low_impact
    #|tag upper_limb
    #|load impact=none
    #|load shoulder=medium
    #|load spine=low
    #|phase raise hold=250 wrist_above_shoulder_left>=0.45 wrist_above_shoulder_right>=0.45
    #|phase lower hold=250 wrist_above_shoulder_left<=-1.20 wrist_above_shoulder_right<=-1.20
    #|cycle raise lower
    #|min_rep_ms 600
    #|hysteresis 0.25
    #|cue 坐直，双脚踩实地面，可以扶着扶手保持稳定
    #|cue 双臂从身体两侧向上举起，抬到自己觉得舒适的高度即可
    #|cue 肩膀不要耸起来，抬到最高点时呼气
    #|
    #|motion seated_torso_brace
    #|name 坐姿躯干支撑（等长）
    #|view side
    #|tag seated
    #|tag low_impact
    #|tag core
    #|tag hold
    #|load impact=none
    #|load spine=low
    #|load hip=low
    #|load balance=none
    #|hold_only_ms 15000
    #|phase brace hold=500 trunk_lean<=6
    #|cue 坐直，双脚踩实，双手可以放在大腿或扶手上
    #|cue 轻轻收紧腹部，把肋骨和骨盆之间的位置固定住，保持均匀呼吸
    #|cue 不要屏气，也不要用力过猛；觉得吃力就缩短保持时间
    #|
    #|audience general
    #|name 一般成年人
    #|note 基线人群：不声明任何额外限制，翻译结果是恒等映射
    #|
    #|audience elderly_knee_pain
    #|name 膝痛 / 老年低冲击人群
    #|limit knee_left<=105
    #|limit knee_right<=105
    #|limit hip_left<=100
    #|limit hip_right<=100
    #|limit ankle_span<=1.20
    #|limit trunk_lean<=15
    #|allow impact=none
    #|allow knee=low
    #|allow balance=medium
    #|note 不包含跳跃、落地、深蹲到底与地面动作
    #|note 本工具给出的是降低关节负荷的变式，不构成医疗建议
    #|
    #|audience wheelchair
    #|name 轮椅使用者
    #|limit knee_left<=110
    #|limit knee_right<=110
    #|limit hip_left<=110
    #|limit hip_right<=110
    #|limit ankle_span<=0.60
    #|limit trunk_lean<=20
    #|allow impact=none
    #|allow knee=low
    #|allow hip=low
    #|allow shoulder=medium
    #|allow balance=none
    #|allow spine=medium
    #|note 所有动作在坐姿完成，去掉站立、平衡与落地成分
    #|note 上肢能抬多高取决于个人活动能力，请按自身情况调整幅度
    #|
    #|audience office_sedentary
    #|name 久坐办公人群
    #|limit ankle_span<=2.20
    #|limit trunk_lean<=25
    #|allow impact=none
    #|allow knee=medium
    #|allow spine=low
    #|note 保留站立动作，只去掉跳跃冲击
    #|note 适合在工位旁完成，不要求地面动作
    #|
    #|variant jumping_jack elderly_knee_pain -> seated_leg_lift
    #|reason 去掉跳跃与落地冲击，把下肢工作改成坐姿抬腿，保留髋与膝的主动活动
    #|
    #|variant squat elderly_knee_pain -> chair_squat
    #|reason 保留蹲起模式，限制下蹲幅度并提供椅背支撑，把膝负荷降到低位
    #|
    #|variant plank elderly_knee_pain -> wall_body_hold
    #|reason 用背贴墙站立替代地面支撑，去掉跪撑与长时间俯卧，保留躯干等长收缩
    #|
    #|variant jumping_jack wheelchair -> seated_arm_raise
    #|reason 保留开合跳的上肢节律，整体改为坐姿，去掉下肢与落地成分
    #|
    #|variant squat wheelchair -> seated_leg_lift
    #|reason 用坐姿抬腿替代负重的蹲起，去掉站立与平衡要求
    #|
    #|variant plank wheelchair -> seated_torso_brace
    #|reason 用坐姿躯干支撑替代地面平板支撑，保留核心等长收缩
    #|
    #|variant jumping_jack office_sedentary -> low_impact_step
    #|reason 保留开合节律与上肢动作，去掉跳跃冲击，可在工位旁完成
    #|
    #|variant squat office_sedentary -> chair_squat
    #|reason 保留蹲起模式，用椅背支撑降低腰与膝的负荷
    #|
    #|variant plank office_sedentary -> wall_body_hold
    #|reason 用靠墙等长收缩替代地面平板支撑，避免长时间俯卧
  )
}

///|
/// 解析内置规则表。
///
/// 每次都重新解析，引擎里不缓存、不放全局状态（调用方要复用就自己缓存）。
/// 规则表只有两三千字节，解析开销可以忽略，换来的是「没有隐藏状态」。
pub fn builtin_program() -> DslProgram {
  parse_program(builtin_source())
}
