// MoveMentor 核心引擎 · 领域模型
//
// 这一层只描述「一帧人体姿态长什么样」，不含任何翻译或计数逻辑，
// 也不依赖任何浏览器 / 摄像头 API，因此可以在 `moon test` 里被完整构造与断言。

///|
/// 引擎依赖的 12 个关键点。
///
/// 取值与 MediaPipe Pose(BlazePose) 33 点模型的索引一一对应，
/// 映射关系见 `Joint::mediapipe_index`。
pub(all) enum Joint {
  LeftShoulder
  RightShoulder
  LeftElbow
  RightElbow
  LeftWrist
  RightWrist
  LeftHip
  RightHip
  LeftKnee
  RightKnee
  LeftAnkle
  RightAnkle
} derive(Debug, Eq)

///|
/// 该关键点在 MediaPipe Pose 33 点输出里的下标。
pub fn Joint::mediapipe_index(self : Joint) -> Int {
  match self {
    LeftShoulder => 11
    RightShoulder => 12
    LeftElbow => 13
    RightElbow => 14
    LeftWrist => 15
    RightWrist => 16
    LeftHip => 23
    RightHip => 24
    LeftKnee => 25
    RightKnee => 26
    LeftAnkle => 27
    RightAnkle => 28
  }
}

///|
/// 稳定的小写标识符，用于指标名、日志与测试断言。
pub fn Joint::token(self : Joint) -> String {
  match self {
    LeftShoulder => "left_shoulder"
    RightShoulder => "right_shoulder"
    LeftElbow => "left_elbow"
    RightElbow => "right_elbow"
    LeftWrist => "left_wrist"
    RightWrist => "right_wrist"
    LeftHip => "left_hip"
    RightHip => "right_hip"
    LeftKnee => "left_knee"
    RightKnee => "right_knee"
    LeftAnkle => "left_ankle"
    RightAnkle => "right_ankle"
  }
}

///|
/// MediaPipe Pose 输出的关键点总数。
pub const POSE_POINT_COUNT : Int = 33

///|
/// 每个关键点在扁平数组里占用的分量数：x, y, z, visibility。
pub const POSE_STRIDE : Int = 4

///|
/// 归一化图像坐标下的单个关键点。
///
/// `x`、`y` 以画面左上角为原点、向右向下为正，取值范围约 0..1；
/// `z` 是相对深度；`visibility` 是该点的置信度。
pub(all) struct Landmark {
  x : Double
  y : Double
  z : Double
  visibility : Double
} derive(Debug)

///|
pub fn Landmark::new(
  x : Double,
  y : Double,
  z : Double,
  visibility : Double,
) -> Landmark {
  { x, y, z, visibility, }
}

///|
/// 图像平面上的欧氏距离。刻意忽略 `z`：正面机位下深度分量噪声较大。
pub fn Landmark::planar_distance(self : Landmark, other : Landmark) -> Double {
  let dx = self.x - other.x
  let dy = self.y - other.y
  (dx * dx + dy * dy).sqrt()
}

///|
/// 两个关键点的中点，用于构造「肩中点 / 髋中点 / 踝中点」这类派生点。
pub fn Landmark::midpoint(self : Landmark, other : Landmark) -> Landmark {
  {
    x: (self.x + other.x) / 2.0,
    y: (self.y + other.y) / 2.0,
    z: (self.z + other.z) / 2.0,
    visibility: (self.visibility + other.visibility) / 2.0,
  }
}

///|
/// 单帧姿态。
///
/// 内部是长度 132（= 33 × 4）的扁平数组。之所以不直接暴露 33 个结构体，
/// 是因为这一层就是与 JS 侧的边界：页面把 `PoseLandmarker` 的输出摊平成
/// 一组数字传进来即可，不需要跨语言构造对象，也便于单元测试里手写一帧。
pub(all) struct PoseFrame {
  points : Array[Double]
}

///|
/// 从扁平数组构造。长度不是 132 时返回 `None`，坏数据不会被静默接受。
pub fn PoseFrame::from_flat(points : Array[Double]) -> PoseFrame? {
  if points.length() == POSE_POINT_COUNT * POSE_STRIDE {
    Some({ points, })
  } else {
    None
  }
}

///|
/// 一帧「空白但可见」的姿态：坐标全为 0，visibility 全为 1。
///
/// 测试里先拿到它再用 `set` 逐个摆放关键点；`visibility` 默认为 1
/// 是为了让测试聚焦在几何上，需要验证低置信度分支时再手动改写。
pub fn PoseFrame::empty() -> PoseFrame {
  let points : Array[Double] = []
  for _ in 0..<POSE_POINT_COUNT {
    points.push(0.0)
    points.push(0.0)
    points.push(0.0)
    points.push(1.0)
  }
  { points, }
}

///|
/// 按 MediaPipe 下标读取任意关键点。
pub fn PoseFrame::point_at(self : PoseFrame, index : Int) -> Landmark {
  let base = index * POSE_STRIDE
  {
    x: self.points[base],
    y: self.points[base + 1],
    z: self.points[base + 2],
    visibility: self.points[base + 3],
  }
}

///|
/// 按关节读取关键点。
pub fn PoseFrame::get(self : PoseFrame, joint : Joint) -> Landmark {
  self.point_at(joint.mediapipe_index())
}

///|
/// 就地写入一个关键点。
pub fn PoseFrame::set(
  self : PoseFrame,
  joint : Joint,
  landmark : Landmark,
) -> Unit {
  self.put_at(joint.mediapipe_index(), landmark)
}

///|
/// 按 MediaPipe 下标就地写入。
pub fn PoseFrame::put_at(
  self : PoseFrame,
  index : Int,
  landmark : Landmark,
) -> Unit {
  let base = index * POSE_STRIDE
  self.points[base] = landmark.x
  self.points[base + 1] = landmark.y
  self.points[base + 2] = landmark.z
  self.points[base + 3] = landmark.visibility
}

///|
/// 两个关节的中点（例如肩中点 = 左右肩的中点）。
pub fn PoseFrame::midpoint_of(
  self : PoseFrame,
  a : Joint,
  b : Joint,
) -> Landmark {
  self.get(a).midpoint(self.get(b))
}

///|
/// 全帧平均可见度，作为「这一帧能不能信」的粗判据。
pub fn PoseFrame::mean_visibility(self : PoseFrame) -> Double {
  let mut acc = 0.0
  for i in 0..<POSE_POINT_COUNT {
    acc = acc + self.points[i * POSE_STRIDE + 3]
  }
  acc / POSE_POINT_COUNT.to_double()
}

///|
/// 只统计引擎真正使用的 12 个关键点的平均可见度。
///
/// 这比全帧平均更有意义：画面里的桌椅、旁人会让无关点位的分数忽高忽低。
pub fn PoseFrame::tracked_visibility(self : PoseFrame) -> Double {
  let joints = tracked_joints()
  let mut acc = 0.0
  for j in joints {
    acc = acc + self.get(j).visibility
  }
  acc / joints.length().to_double()
}

///|
/// 引擎实际读取的关键点清单。
pub fn tracked_joints() -> Array[Joint] {
  [
    LeftShoulder,
    RightShoulder,
    LeftElbow,
    RightElbow,
    LeftWrist,
    RightWrist,
    LeftHip,
    RightHip,
    LeftKnee,
    RightKnee,
    LeftAnkle,
    RightAnkle,
  ]
}
