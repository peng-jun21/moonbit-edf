///|
/// Event-aligned data, retaining the source annotation and absolute file times.
/// Complete means the requested interval is inside the recorded domain without
/// a known inter-record gap; it is not a claim about signal quality or diagnosis.
pub struct EventWindow {
  annotation_index : Int
  annotation : Annotation
  start : Double
  end : Double
  complete : Bool
  samples : Int
  channels : Array[SignalWindow]
} derive(Debug, ToJson)

///|
pub extend EventWindow with @debug.Debug::{to_repr}

///|
pub extend EventWindow with ToJson::{to_json}

///|
// Reuse the writer's 100 ns representability/range check, then add integer
// ticks. Adding binary seconds first can include the excluded endpoint (e.g.
// 20.8 + 4.1 + .25 becomes 25.150000000000002 instead of 25.15).
fn event_ticks(value : Double) -> Int64 raise EdfError {
  ignore(time_text(value, true))
  (value * 10000000.0).round().to_int64()
}

///|
/// Select by annotation index, never ambiguous event text. Seconds remain
/// relative to the original file origin. All channels share a sample budget.
/// Missing recording time is rejected by default, never padded/interpolated.
pub fn Recording::event_window(
  self : Recording,
  annotation_index : Int,
  signals : Array[Int],
  before~ : Double,
  after~ : Double,
  include_duration? : Bool = true,
  allow_partial? : Bool = false,
  max_samples? : Int = 65536,
) -> EventWindow raise EdfError {
  if annotation_index < 0 || annotation_index >= self.annotations.length() {
    raise Invalid("event window annotation index")
  }
  if !finite(before) || !finite(after) || before < 0.0 || after < 0.0 {
    raise Invalid("event padding requires finite nonnegative seconds")
  }
  if signals.is_empty() || self.records == 0 {
    raise Invalid("event window requires signals and records")
  }
  let annotation = self.annotations[annotation_index]
  let duration = if include_duration {
    annotation.duration.unwrap_or(0.0)
  } else {
    0.0
  }
  let onset_ticks = event_ticks(annotation.onset)
  let start = (onset_ticks - event_ticks(before)).to_double() / 10000000.0
  let end = (onset_ticks + event_ticks(duration) + event_ticks(after)).to_double() /
    10000000.0
  ignore(time_text(start, true))
  ignore(time_text(end, true))
  check_window(start, end, max_samples)
  if start >= end {
    raise Invalid("event window must have positive duration")
  }
  let mut complete = start >= self.starts[0] &&
    end <= self.starts[self.records - 1] + self.header.duration
  for gap in self.gaps() {
    if gap.start < end && gap.end > start {
      complete = false
    }
  }
  if !complete && !allow_partial {
    raise Invalid(
      "event window crosses missing recording time; explicitly allow_partial to retain it",
    )
  }
  let seen : Map[Int, Bool] = Map([])
  let mut samples = 0
  // Preflight every channel before allocating sample objects.
  for signal in signals {
    if seen.contains(signal) {
      raise Invalid("event window signals must be distinct")
    }
    seen[signal] = true
    let (_, count) = self.window_spans(
      signal,
      start,
      end,
      max_samples - samples,
    )
    samples += count
  }
  let channels = signals.map(signal => {
    self.time_window(signal, start, end, max_samples~)
  })
  { annotation_index, annotation, start, end, complete, samples, channels, }
}
