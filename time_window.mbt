///|
/// A sample retains its zero-based source record and within-record sample index.
pub struct TimedSample {
  record : Int
  sample : Int
  time : Double
  digital : Int
  physical : Double
} derive(Debug, ToJson)

///|
/// An interval in seconds relative to the original header origin, not a new file.
/// Gaps are intersections with known inter-record gaps, not extrapolated padding.
pub struct SignalWindow {
  signal : Int
  label : String
  unit : String
  start : Double
  end : Double
  samples : Array[TimedSample]
  gaps : Array[Gap]
} derive(Debug, ToJson)

///|
pub extend TimedSample with @debug.Debug::{to_repr}

///|
pub extend SignalWindow with @debug.Debug::{to_repr}

///|
pub extend TimedSample with ToJson::{to_json}

///|
pub extend SignalWindow with ToJson::{to_json}

///|
fn check_window(
  start : Double,
  end : Double,
  max_samples : Int,
) -> Unit raise EdfError {
  if !finite(start) || !finite(end) || start > end {
    raise Invalid("window requires finite start <= end seconds")
  }
  if max_samples < 1 || max_samples > 1000000 {
    raise Invalid("window sample limit must be between 1 and 1000000")
  }
}

///|
// Match sample_time's floating-point expression exactly. Searching timestamps,
// rather than rounding (bound-onset)*rate, keeps exact endpoint membership and
// supports zero-duration event records without dividing by their duration.
fn time_lower_bound(
  onset : Double,
  duration : Double,
  per : Int,
  bound : Double,
) -> Int {
  let mut lo = 0
  let mut hi = per
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if onset + duration * mid.to_double() / per.to_double() < bound {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
// Preflight selection and its budget before materializing values. Tuples are
// (record, first sample, exclusive end); limits apply to samples, not records.
fn Recording::window_spans(
  self : Recording,
  signal : Int,
  start : Double,
  end : Double,
  budget : Int,
) -> (Array[(Int, Int, Int)], Int) raise EdfError {
  if signal < 0 ||
    signal >= self.header.signals.length() ||
    self.header.signals[signal].is_annotation() {
    raise Invalid("ordinary signal index required")
  }
  let spans = []
  let mut count = 0
  if start == end {
    return (spans, count)
  }
  let per = self.header.signals[signal].samples_per_record
  for r = 0; r < self.records; r = r + 1 {
    let onset = self.starts[r]
    if !finite(
        onset + self.header.duration * (per - 1).to_double() / per.to_double(),
      ) {
      raise Limit("window sample timestamp overflow")
    }
    let first = time_lower_bound(onset, self.header.duration, per, start)
    let last = time_lower_bound(onset, self.header.duration, per, end)
    if last - first > budget - count {
      raise Limit("window exceeds requested sample limit")
    }
    if first < last {
      spans.push((r, first, last))
      count += last - first
    }
    // Do not stop early: decode tolerates sub-100ns backwards timekeeping noise.
  }
  (spans, count)
}

///|
/// Extract samples whose timestamps are in [start, end), in source-file order.
/// Bounds are finite seconds relative to the original header; negative bounds
/// are allowed. No interpolation, resampling, rebasing or gap filling occurs.
/// Equal bounds return an empty window. Exceeding max_samples raises Limit;
/// nothing is silently truncated. Physical calibration failures are propagated.
pub fn Recording::time_window(
  self : Recording,
  signal : Int,
  start : Double,
  end : Double,
  max_samples? : Int = 65536,
) -> SignalWindow raise EdfError {
  check_window(start, end, max_samples)
  let (spans, _) = self.window_spans(signal, start, end, max_samples)
  let s = self.header.signals[signal]
  let samples = []
  for span in spans {
    let (r, first, last) = span
    for j = first; j < last; j = j + 1 {
      let digital = self.digital(signal, r, j)
      samples.push({
        record: r,
        sample: j,
        time: self.sample_time(signal, r, j),
        digital,
        physical: s.to_physical(digital),
      })
    }
  }
  let gaps = []
  if start < end {
    for r = 1; r < self.records; r = r + 1 {
      let previous_end = self.starts[r - 1] + self.header.duration
      if self.starts[r] - previous_end > 1.0e-7 {
        let lo = previous_end.max(start)
        let hi = self.starts[r].min(end)
        if lo < hi {
          gaps.push({ after_record: r - 1, start: lo, end: hi, })
        }
      }
    }
  }
  { signal, label: s.label, unit: s.unit, start, end, samples, gaps, }
}

///|
/// Long-form time-window CSV, grouped by requested channel, then source order.
/// Original indices/times are retained; there are no rows for missing time.
/// At least one distinct ordinary channel is required. The row budget is shared
/// across channels and checked before any values or CSV strings are generated.
pub fn Recording::window_csv(
  self : Recording,
  indices : Array[Int],
  start : Double,
  end : Double,
  physical? : Bool = true,
  max_samples? : Int = 65536,
) -> String raise EdfError {
  check_window(start, end, max_samples)
  if indices.is_empty() {
    raise Invalid("window CSV requires at least one ordinary signal")
  }
  let seen : Map[Int, Bool] = Map([])
  let selections = []
  let mut rows = 0
  for s in indices {
    if seen.contains(s) {
      raise Invalid("window CSV signal indices must be distinct")
    }
    seen[s] = true
    let (spans, count) = self.window_spans(s, start, end, max_samples - rows)
    rows += count
    selections.push((s, spans))
  }
  let lines = ["signal,label,record,sample,time_seconds,value,unit"]
  for selection in selections {
    let (s, spans) = selection
    let signal = self.header.signals[s]
    let label = csv_quote(signal.label)
    let unit = csv_quote(if physical { signal.unit } else { "digital" })
    for span in spans {
      let (r, first, last) = span
      for j = first; j < last; j = j + 1 {
        let value = if physical {
          self.physical(s, r, j).to_string()
        } else {
          self.digital(s, r, j).to_string()
        }
        lines.push(
          "\{s},\{label},\{r},\{j},\{self.sample_time(s,r,j)},\{value},\{unit}",
        )
      }
    }
  }
  lines.join("\n") + "\n"
}
