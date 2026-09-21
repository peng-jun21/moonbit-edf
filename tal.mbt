///|
/// Parse signed onset or unsigned duration, forbidding exponents/control syntax.
fn tal_number(text : String, onset : Bool) -> Double raise EdfError {
  if text.length() == 0 || text.length() > 128 {
    raise Invalid("invalid TAL time length")
  }
  let start = if onset {
    if text[0] != '+' && text[0] != '-' {
      raise Invalid("TAL onset requires sign")
    }
    1
  } else {
    0
  }
  let mut dots = 0
  let mut digits = 0
  for i = start; i < text.length(); i = i + 1 {
    let c = text[i]
    if c == '.' {
      dots += 1
      if dots > 1 || i == start || i == text.length() - 1 {
        raise Invalid("malformed TAL decimal")
      }
    } else if c >= '0' && c <= '9' {
      digits += 1
    } else {
      raise Invalid("TAL time must be a plain decimal")
    }
  }
  if digits == 0 {
    raise Invalid("empty TAL timestamp")
  }
  let value = number(text)
  if value.abs() > 2147483647.0 {
    raise Limit("TAL timestamp exceeds supported 68-year relative range")
  }
  value
}

///|
/// Preserve decimal spelling and grouped annotation texts.
pub fn parse_tals(data : Bytes) -> Array[Tal] raise EdfError {
  if data.length() > 8388608 {
    raise Limit("TAL block exceeds 8 MiB")
  }
  let result = []
  let mut at = 0
  while at < data.length() && data[at] != b'\x00' {
    let start = at
    while at < data.length() &&
          data[at] != b'\x14' &&
          data[at] != b'\x15' &&
          data[at] != b'\x00' {
      at += 1
    }
    if at == data.length() || data[at] == b'\x00' {
      raise Invalid("TAL missing annotation separator")
    }
    let onset = text_field(data, start, at - start)
    if onset.length() != at - start {
      raise Invalid("spaces are forbidden in TAL onset")
    }
    ignore(tal_number(onset, true))
    let duration = if data[at] == b'\x15' {
      at += 1
      let start = at
      while at < data.length() && data[at] != b'\x14' && data[at] != b'\x00' {
        at += 1
      }
      if at == data.length() || data[at] != b'\x14' {
        raise Invalid("TAL duration missing separator")
      }
      let duration = text_field(data, start, at - start)
      if duration.length() != at - start {
        raise Invalid("spaces are forbidden in TAL duration")
      }
      ignore(tal_number(duration, false))
      Some(duration)
    } else {
      None
    }
    at += 1
    let texts = []
    while true {
      let start = at
      while at < data.length() && data[at] != b'\x14' && data[at] != b'\x00' {
        let b = data[at].to_int()
        if b < 32 && b != 9 && b != 10 && b != 13 {
          raise Invalid("forbidden TAL control character")
        }
        at += 1
      }
      if at == data.length() || data[at] != b'\x14' {
        raise Invalid("TAL text requires final separator")
      }
      let text = @utf8.decode(data[start:at], ignore_bom=false) catch {
        _ => raise Invalid("malformed UTF-8 annotation")
      }
      texts.push(text)
      at += 1
      if at >= data.length() {
        raise Invalid("TAL missing zero terminator")
      }
      if data[at] == b'\x00' {
        at += 1
        break
      }
    }
    if result.length() >= 65536 {
      raise Limit("TAL count per block exceeds 65536")
    }
    result.push({ onset, duration, texts, })
  }
  while at < data.length() {
    if data[at] != b'\x00' {
      raise Invalid("nonzero bytes after TAL padding")
    }
    at += 1
  }
  result
}

///|
pub fn encode_tals(tals : Array[Tal], capacity : Int) -> Bytes raise EdfError {
  if capacity < 0 || capacity > 8388608 {
    raise Limit("TAL capacity exceeds limit")
  }
  let out = Array::make(capacity, b'\x00')
  let mut at = 0
  for tal in tals {
    ignore(tal_number(tal.onset, true))
    let duration = match tal.duration {
      Some(d) => {
        ignore(tal_number(d, false))
        "\u0015" + d
      }
      None => ""
    }
    if tal.texts.is_empty() {
      raise Invalid("TAL must contain at least one text, possibly empty")
    }
    for text in tal.texts {
      for c in text.iter() {
        if c.to_int() < 32 && c != '\t' && c != '\n' && c != '\r' {
          raise Invalid("forbidden TAL control character")
        }
      }
    }
    let b = @utf8.encode(
      tal.onset +
      duration +
      "\u0014" +
      tal.texts.join("\u0014") +
      "\u0014\u0000",
    )
    if b.length() > capacity - at {
      raise Limit("annotations do not fit record capacity")
    }
    copy_bytes(out, at, b, 0, b.length())
    at += b.length()
  }
  Bytes::from_array(out)
}

///|
/// New timestamps use the common EDF library resolution of 100 ns.
fn time_text(value : Double, signed : Bool) -> String raise EdfError {
  if !finite(value) || value.abs() > 2147483647.0 || (!signed && value < 0.0) {
    raise Invalid("invalid timestamp")
  }
  let ticks = (value.abs() * 10000000.0).round().to_int64()
  if (ticks.to_double() / 10000000.0 - value.abs()).abs() > 1.0e-8 {
    raise Unsupported("timestamp cannot be represented at 100 ns precision")
  }
  let whole = (ticks / 10000000L).to_string()
  let frac = ticks % 10000000L
  let tail = if frac == 0L {
    ""
  } else {
    let padded = (10000000L + frac).to_string()
    let mut end = padded.length()
    while end > 1 && padded[end - 1] == '0' {
      end -= 1
    }
    "." + padded[1:end].to_owned()
  }
  (if value < 0.0 { "-" } else if signed { "+" } else { "" }) + whole + tail
}
