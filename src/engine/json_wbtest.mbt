// JSON 写出器的白盒测试。
//
// 它只有几十行，但它是引擎与浏览器之间的唯一通道：
// 少转义一个引号，整个页面就白屏。所以边界值要一个个试。

///|
test "json: 基本字段" {
  let object = JsonObject::new()
  object.field_int("reps", 3)
  object.field_bool("ok", true)
  object.field_string("name", "坐姿抬腿")
  assert_eq(
    object.finish(),
    "{\"reps\": 3, \"ok\": true, \"name\": \"坐姿抬腿\"}",
  )
}

///|
test "json: 空对象" {
  assert_eq(JsonObject::new().finish(), "{}")
}

///|
test "json: 转义引号、反斜杠与换行" {
  let object = JsonObject::new()
  object.field_string("text", "说\"话\"\\反斜杠\n换行")
  assert_eq(
    object.finish(),
    "{\"text\": \"说\\\"话\\\"\\\\反斜杠\\n换行\"}",
  )
}

///|
test "json: 字符串数组" {
  let object = JsonObject::new()
  object.field_string_array("cues", ["第一条", "第二条"])
  assert_eq(object.finish(), "{\"cues\": [\"第一条\", \"第二条\"]}")
  let empty = JsonObject::new()
  empty.field_string_array("cues", [])
  assert_eq(empty.finish(), "{\"cues\": []}")
}

///|
test "json: 数字与非法值" {
  assert_eq(json_number(1.5), "1.5")
  assert_eq(json_number(-2.0), "-2")
  assert_eq(json_number(0.0), "0")
  // NaN / Infinity 不是合法 JSON，写成 null 而不是让下游解析炸掉
  assert_eq(json_number(0.0 / 0.0), "null")
  assert_eq(json_number(1.0 / 0.0), "null")
  assert_eq(json_number(-1.0 / 0.0), "null")
}

///|
test "json: 字段数决定逗号位置" {
  let object = JsonObject::new()
  object.field_int("a", 1)
  object.field_double("b", 0.5)
  assert_eq(object.finish(), "{\"a\": 1, \"b\": 0.5}")
}
