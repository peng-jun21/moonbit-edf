///|
extern "js" fn fail_bytes(message : String) -> Bytes =
  #| (message) => { throw new Error(message); }

///|
extern "js" fn fail_string(message : String) -> String =
  #| (message) => { throw new Error(message); }

///|
fn object(text : String) -> Map[String, Json] raise {
  if text.length() > 1000000 {
    raise Failure("options exceed one million characters")
  }
  match @json.parse(text) {
    Object(o) => o
    _ => raise Failure("options must be an object")
  }
}

///|
fn[T : @json.FromJson] required(o : Map[String, Json], key : String) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => raise Failure("missing option: " + key)
  }
}

///|
fn[T : @json.FromJson] optional(
  o : Map[String, Json],
  key : String,
  fallback : T,
) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => fallback
  }
}

///|
fn do_report(data : Bytes, text : String) -> String raise {
  let o = object(text)
  let recording = @lib.decode(data)
  let h = recording.header
  let cmd : String = optional(o, "command", "inspect")
  let result : Json = match cmd {
    "inspect" | "validate" =>
      {
        "format": (if h.format == @lib.Edf { "edf" } else { "bdf" }).to_json(),
        "continuity": (match h.continuity {
          @lib.Plain => "plain"
          @lib.Continuous => "continuous"
          @lib.Discontinuous => "discontinuous"
        }).to_json(),
        "records": recording.records.to_json(),
        "declared_records": h.declared_records.to_json(),
        "duration": h.duration.to_json(),
        "date": h.date.to_json(),
        "time": h.time.to_json(),
        "patient": h.patient.to_json(),
        "recording": h.recording.to_json(),
        "signals": h.signals.to_json(),
        "starts": recording.starts.to_json(),
        "annotations": recording.annotations.length().to_json(),
        "gaps": recording.gaps().to_json(),
      }
    "stats" => recording.statistics(required(o, "signal")).to_json()
    "annotations" => recording.annotations.to_json()
    "gaps" => recording.gaps().to_json()
    "flat" =>
      recording
      .flat_runs(required(o, "signal"), required(o, "minimum_samples"))
      .to_json()
    "csv" => {
      let first : Int = optional(o, "first_record", 0)
      {
        "text": recording
        .csv(
          required(o, "signals"),
          first_record=first,
          records=optional(o, "records", recording.records - first),
          physical=optional(o, "physical", true),
        )
        .to_json(),
      }
    }
    "channel" => {
      let s : Int = required(o, "signal")
      if s < 0 || s >= h.signals.length() || h.signals[s].is_annotation() {
        raise Failure("ordinary signal index required")
      }
      let per = h.signals[s].samples_per_record
      let start : Int = optional(o, "start", 0)
      let count : Int = optional(
        o,
        "count",
        (recording.records * per).min(65536),
      )
      if start < 0 ||
        count < 0 ||
        count > 65536 ||
        start > recording.records * per ||
        count > recording.records * per - start {
        raise Failure("invalid sample range, maximum 65536")
      }
      let values = Array::makei(count, i => {
        if optional(o, "physical", false) {
          recording.physical(s, (start + i) / per, (start + i) % per)
        } else {
          recording.digital(s, (start + i) / per, (start + i) % per).to_double()
        }
      })
      let times = Array::makei(count, i => {
        recording.sample_time(s, (start + i) / per, (start + i) % per)
      })
      { "values": values.to_json(), "times": times.to_json() }
    }
    _ => raise Failure("unknown report command")
  }
  result.stringify()
}

///|
pub fn report(data : Bytes, options : String) -> String {
  do_report(data, options) catch {
    e => fail_string(@debug.to_string(e))
  }
}

///|
fn from_options(o : Map[String, Json]) -> @lib.Recording raise {
  let format = match optional(o, "format", "edf") {
    "edf" => @lib.Edf
    "bdf" => @lib.Bdf
    _ => raise Failure("format must be edf or bdf")
  }
  let continuity = match optional(o, "continuity", "continuous") {
    "plain" => @lib.Plain
    "continuous" => @lib.Continuous
    "discontinuous" => @lib.Discontinuous
    _ => raise Failure("invalid continuity")
  }
  let descriptions : Array[Map[String, Json]] = required(o, "signals")
  let signals : Array[@lib.Signal] = descriptions.map(d => {
    label: required(d, "label"),
    transducer: optional(d, "transducer", ""),
    unit: optional(d, "unit", "uV"),
    physical_min: optional(d, "physical_min", -100.0),
    physical_max: optional(d, "physical_max", 100.0),
    digital_min: optional(
      d,
      "digital_min",
      if format == @lib.Edf {
        -32768
      } else {
        -8388608
      },
    ),
    digital_max: optional(
      d,
      "digital_max",
      if format == @lib.Edf {
        32767
      } else {
        8388607
      },
    ),
    prefilter: optional(d, "prefilter", ""),
    samples_per_record: required(d, "samples_per_record"),
    reserved: "",
  })
  let input_records : Array[Map[String, Json]] = required(o, "records")
  let records : Array[@lib.Record] = input_records.map(r => {
    onset: required(r, "onset"),
    samples: required(r, "samples"),
    events: optional(r, "events", []),
  })
  let date : String = optional(o, "date", "01.01.20")
  let time : String = optional(o, "time", "00.00.00")
  @lib.create(
    signals,
    records,
    required(o, "duration"),
    format~,
    continuity~,
    start=@lib.parse_datetime(date, time),
    patient=optional(o, "patient", "X X X X"),
  )
}

///|
fn do_transform(data : Bytes, text : String) -> Bytes raise {
  let o = object(text)
  let cmd : String = required(o, "command")
  let recording = if cmd == "create" {
    from_options(o)
  } else {
    let r = @lib.decode(data)
    match cmd {
      "copy" => r
      "select" => r.select(required(o, "signals"))
      "crop" => r.crop(required(o, "first_record"), required(o, "records"))
      "plus" => r.to_plus()
      _ => raise Failure("unknown transform command")
    }
  }
  recording.encode()
}

///|
pub fn transform(data : Bytes, options : String) -> Bytes {
  do_transform(data, options) catch {
    e => fail_bytes(@debug.to_string(e))
  }
}

///|
fn main {

}
