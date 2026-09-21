///|
/// Select ordinary channels, preserving all annotation channels and record timing.
pub fn Recording::select(
  self : Recording,
  indices : Array[Int],
) -> Recording raise EdfError {
  if indices.is_empty() {
    raise Invalid("select at least one ordinary channel")
  }
  let selected = indices.copy()
  let seen : Map[Int, Bool] = Map([])
  for s in indices {
    if s < 0 ||
      s >= self.header.signals.length() ||
      self.header.signals[s].is_annotation() {
      raise Invalid("selection requires ordinary signal indices")
    }
    if seen.contains(s) {
      raise Invalid("duplicate selected signal")
    }
    seen[s] = true
  }
  for s = 0; s < self.header.signals.length(); s = s + 1 {
    if self.header.signals[s].is_annotation() {
      selected.push(s)
    }
  }
  let n = selected.length()
  let oldn = self.header.signals.length()
  let hs = 256 + n * 256
  let mut rs = 0
  for s in selected {
    rs += self.header.signals[s].samples_per_record * self.header.format.width()
  }
  let out = Array::make(hs + rs * self.records, b'\x00')
  copy_bytes(out, 0, self.data, 0, 256)
  put_text(out, 184, 8, hs.to_string())
  put_text(out, 252, 4, n.to_string())
  put_text(out, 236, 8, self.records.to_string())
  let mut cumulative = 0
  for width in [16, 80, 8, 8, 8, 8, 8, 80, 8, 32] {
    for i = 0; i < n; i = i + 1 {
      copy_bytes(
        out,
        256 + n * cumulative + i * width,
        self.data,
        256 + oldn * cumulative + selected[i] * width,
        width,
      )
    }
    cumulative += width
  }
  for r = 0; r < self.records; r = r + 1 {
    let mut at = hs + r * rs
    for s in selected {
      let size = self.header.signals[s].samples_per_record *
        self.header.format.width()
      copy_bytes(
        out,
        at,
        self.data,
        self.header.bytes +
        r * self.header.record_bytes +
        self.header.offsets[s],
        size,
      )
      at += size
    }
  }
  decode(Bytes::from_array(out))
}

///|
fn checked_time_value(text : String, onset : Bool) -> Double raise EdfError {
  let mut after_dot = -1
  for c in text.iter() {
    if c == '.' {
      after_dot = 0
    } else if after_dot >= 0 {
      after_dot += 1
      if after_dot > 7 && c != '0' {
        raise Unsupported("time transform would lose sub-100ns precision")
      }
    }
  }
  tal_number(text, onset)
}

///|
/// Crop whole records. EDF+ timestamps are rebased; dates advance across midnight.
pub fn Recording::crop(
  self : Recording,
  first : Int,
  count : Int,
) -> Recording raise EdfError {
  if first < 0 ||
    count < 1 ||
    first >= self.records ||
    count > self.records - first {
    raise Invalid("crop record range out of bounds")
  }
  let h = self.header
  let start = self.starts[first]
  let shift = start.floor().to_int()
  if h.continuity == Plain && start != shift.to_double() {
    raise Unsupported(
      "plain EDF/BDF cannot represent a fractional cropped origin; convert to plus before cropping",
    )
  }
  let date = parse_datetime(h.date, h.time).advance(shift)
  let out = Array::make(h.bytes + count * h.record_bytes, b'\x00')
  copy_bytes(out, 0, self.data, 0, h.bytes)
  copy_bytes(
    out,
    h.bytes,
    self.data,
    h.bytes + first * h.record_bytes,
    count * h.record_bytes,
  )
  put_text(out, 168, 8, date.date_field())
  put_text(out, 176, 8, date.time_field())
  put_text(out, 236, 8, count.to_string())
  if h.continuity != Plain {
    let tokens = h.recording
      .split(" ")
      .filter(x => !x.is_empty())
      .map(x => x.to_owned())
      .collect()
    if tokens.length() < 5 || tokens[0] != "Startdate" {
      raise Invalid("cannot update malformed plus recording identification")
    }
    tokens[1] = date.long_date()
    put_text(out, 88, 80, tokens.join(" "))
    for r = 0; r < count; r = r + 1 {
      for s = 0; s < h.signals.length(); s = s + 1 {
        let signal = h.signals[s]
        if !signal.is_annotation() {
          continue
        }
        let capacity = signal.samples_per_record * h.format.width()
        let at = h.bytes + r * h.record_bytes + h.offsets[s]
        let tals = parse_tals(
          part(
            self.data,
            h.bytes + (first + r) * h.record_bytes + h.offsets[s],
            capacity,
          ),
        )
        let changed = tals.map(t => {
          (
            {
              onset: time_text(
                checked_time_value(t.onset, true) - shift.to_double(),
                true,
              ),
              duration: t.duration,
              texts: t.texts,
            } : Tal)
        })
        let b = encode_tals(changed, capacity)
        copy_bytes(out, at, b, 0, capacity)
      }
    }
  }
  decode(Bytes::from_array(out))
}

///|
/// Promote a plain recording to plus without altering its samples/calibration text.
/// Existing plus files are returned unchanged. The original recording ID is kept as an annotation.
pub fn Recording::to_plus(self : Recording) -> Recording raise EdfError {
  let h = self.header
  if h.continuity != Plain {
    return self
  }
  let ns = h.signals.length()
  if ns >= 4096 {
    raise Limit("no room for annotation channel")
  }
  let dt = parse_datetime(h.date, h.time)
  let label = if h.format == Edf {
    "EDF Annotations"
  } else {
    "BDF Annotations"
  }
  let capacity = 256
  let samples = (capacity + h.format.width() - 1) / h.format.width()
  let width = samples * h.format.width()
  let hs = 256 + (ns + 1) * 256
  let rs = h.record_bytes + width
  if rs > 8388608 || self.records > (268435456 - hs) / rs {
    raise Limit("promoted recording exceeds resource limit")
  }
  let out = Array::make(hs + self.records * rs, b'\x00')
  copy_bytes(out, 0, self.data, 0, 256)
  put_text(out, 184, 8, hs.to_string())
  put_text(out, 192, 44, if h.format == Edf { "EDF+C" } else { "BDF+C" })
  put_text(out, 252, 4, (ns + 1).to_string())
  put_text(out, 236, 8, self.records.to_string())
  put_text(out, 88, 80, "Startdate " + dt.long_date() + " X X X")
  let vals = [
    label,
    "",
    "",
    "-1",
    "1",
    if h.format == Edf {
      "-32768"
    } else {
      "-8388608"
    },
    if h.format == Edf {
      "32767"
    } else {
      "8388607"
    },
    "",
    samples.to_string(),
    "",
  ]
  let mut cumulative = 0
  let widths = [16, 80, 8, 8, 8, 8, 8, 80, 8, 32]
  for i = 0; i < widths.length(); i = i + 1 {
    let w = widths[i]
    copy_bytes(
      out,
      256 + (ns + 1) * cumulative,
      self.data,
      256 + ns * cumulative,
      ns * w,
    )
    put_text(out, 256 + (ns + 1) * cumulative + ns * w, w, vals[i])
    cumulative += w
  }
  for r = 0; r < self.records; r = r + 1 {
    copy_bytes(
      out,
      hs + r * rs,
      self.data,
      h.bytes + r * h.record_bytes,
      h.record_bytes,
    )
    let tals : Array[Tal] = [
      { onset: time_text(self.starts[r], true), duration: None, texts: [""], },
    ]
    if r == 0 && !h.recording.is_empty() {
      tals.push({
        onset: "+0",
        duration: None,
        texts: ["Original recording ID: " + h.recording],
      })
    }
    let b = encode_tals(tals, width)
    copy_bytes(out, hs + r * rs + h.record_bytes, b, 0, width)
  }
  decode(Bytes::from_array(out))
}
