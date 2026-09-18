// MoveMentor 核心引擎 · 极简 JSON 写出器
//
// 引擎与 JS 侧之间只传字符串。这样做的代价是需要一个写出器，
// 收益是整个 FFI 边界退化成「字符串进、字符串出」——
// 没有共享对象的生命周期问题，也没有跨语言的内存所有权问题。
//
// 只支持扁平对象（字段为 字符串 / 数字 / 布尔 / 字符串数组），
// 因为引擎的输出结构本来就是扁平的。保持能力最小，是为了让审查成本最低。

///|
/// 一个正在构造中的 JSON 对象。
pub struct JsonObject {
  buffer : StringBuilder
  mut count : Int
}

///|
/// 构造一个空对象。
///
/// 提供这个自由函数而不是要求调用方写 `JsonObject::new()`：
/// 跨包使用时不必先命名类型，边界层可以只依赖「拿到一个对象、往里塞字段」。
pub fn json_object() -> JsonObject {
  JsonObject::new()
}

///|
pub fn JsonObject::new() -> JsonObject {
  { buffer: StringBuilder(), count: 0, }
}

///|
fn JsonObject::before_field(self : JsonObject, key : String) -> Unit {
  if self.count > 0 {
    self.buffer.write_string(", ")
  }
  self.count = self.count + 1
  escape_into(self.buffer, key)
  self.buffer.write_string(": ")
}

///|
pub fn JsonObject::field_string(
  self : JsonObject,
  key : String,
  value : String,
) -> Unit {
  self.before_field(key)
  escape_into(self.buffer, value)
}

///|
pub fn JsonObject::field_double(
  self : JsonObject,
  key : String,
  value : Double,
) -> Unit {
  self.before_field(key)
  self.buffer.write_string(json_number(value))
}

///|
pub fn JsonObject::field_int(
  self : JsonObject,
  key : String,
  value : Int,
) -> Unit {
  self.before_field(key)
  self.buffer.write_string("\{value}")
}

///|
pub fn JsonObject::field_bool(
  self : JsonObject,
  key : String,
  value : Bool,
) -> Unit {
  self.before_field(key)
  if value {
    self.buffer.write_string("true")
  } else {
    self.buffer.write_string("false")
  }
}

///|
pub fn JsonObject::field_string_array(
  self : JsonObject,
  key : String,
  values : Array[String],
) -> Unit {
  self.before_field(key)
  self.buffer.write_string("[")
  let mut index = 0
  for value in values {
    if index > 0 {
      self.buffer.write_string(", ")
    }
    index = index + 1
    escape_into(self.buffer, value)
  }
  self.buffer.write_string("]")
}

///|
pub fn JsonObject::finish(self : JsonObject) -> String {
  let out = StringBuilder()
  out.write_string("{")
  out.write_string(self.buffer.to_string())
  out.write_string("}")
  out.to_string()
}

///|
/// JSON 数字。非有限值写成 `null`，宁缺毋滥——下游 `JSON.parse` 不会因此炸掉。
pub fn json_number(value : Double) -> String {
  if value != value {
    "null"
  } else if value > 1.7e308 || value < -1.7e308 {
    "null"
  } else {
    value.to_string()
  }
}

///|
/// 字符串转义。中文字符原样保留，只处理会破坏 JSON 结构的字符。
pub fn escape_into(buffer : StringBuilder, value : String) -> Unit {
  buffer.write_string("\"")
  for c in value {
    if c == '"' {
      buffer.write_string("\\\"")
    } else if c == '\\' {
      buffer.write_string("\\\\")
    } else if c == '\n' {
      buffer.write_string("\\n")
    } else if c == '\r' {
      buffer.write_string("\\r")
    } else if c == '\t' {
      buffer.write_string("\\t")
    } else {
      buffer.write_char(c)
    }
  }
  buffer.write_string("\"")
}
