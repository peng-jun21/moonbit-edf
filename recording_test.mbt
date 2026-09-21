///|
fn signal(samples : Int, format : @edf.Format) -> @edf.Signal {
  {
    label: "Synthetic",
    transducer: "",
    unit: "uV",
    physical_min: 100.0,
    physical_max: -100.0,
    digital_min: if format == @edf.Edf {
      -32768
    } else {
      -8388608
    },
    digital_max: if format == @edf.Edf {
      32767
    } else {
      8388607
    },
    prefilter: "",
    samples_per_record: samples,
    reserved: "",
  }
}

///|
test "EDF and BDF preserve extrema negative gain annotations and differing rates" {
  for format in [@edf.Edf, @edf.Bdf] {
    let s = signal(4, format)
    let recs : Array[@edf.Record] = [
      {
        onset: 0.25,
        samples: [[s.digital_min, 0, 0, s.digital_max], [10, 20]],
        events: [{ onset: 0.5, duration: Some(0.25), text: "标记 α", }],
      },
      { onset: 1.25, samples: [[1, 1, 1, 1], [30, 40]], events: [], },
    ]
    let recording = @edf.create([s, signal(2, format)], recs, 1.0, format~)
    assert_eq(recording.sample_rate(0), 4.0)
    assert_eq(recording.sample_rate(1), 2.0)
    assert_eq(recording.physical(0, 0, 0), 100.0)
    assert_eq(recording.physical(0, 0, 3), -100.0)
    assert_eq(recording.annotations[0].text, "标记 α")
    assert_eq(@edf.decode(recording.encode()).digital(0, 0, 3), s.digital_max)
    assert_eq(recording.flat_runs(0, 3)[0].samples, 4)
    let selected = recording.select([1])
    assert_eq(selected.header.signals.length(), 2)
    assert_eq(selected.annotations[0].text, "标记 α")
    assert_eq(selected.digital(0, 1, 1), 40)
  }
}

///|
test "discontinuous timeline crop advances date and preserves sample event relation" {
  let recs : Array[@edf.Record] = [
    { onset: 0.5, samples: [[1, 2]], events: [], },
    {
      onset: 2.5,
      samples: [[3, 4]],
      events: [{ onset: 2.75, duration: None, text: "event", }],
    },
  ]
  let recording = @edf.create(
    [signal(2, @edf.Edf)],
    recs,
    1.0,
    continuity=@edf.Discontinuous,
    start={ year: 2020, month: 2, day: 28, hour: 23, minute: 59, second: 59, },
  )
  assert_eq(recording.gaps()[0].start, 1.5)
  let cropped = recording.crop(1, 1)
  assert_eq(cropped.header.date, "29.02.20")
  assert_eq(cropped.header.time, "00.00.01")
  assert_eq(cropped.starts, [0.5])
  assert_eq(cropped.annotations[0].onset, 0.75)
  assert_eq(cropped.digital(0, 0, 0), 3)
}

///|
test "fractional plain origin can be promoted and safely cropped" {
  let r = @edf.create(
    [signal(1, @edf.Edf)],
    [
      { onset: 0.0, samples: [[1]], events: [], },
      { onset: 0.5, samples: [[2]], events: [], },
    ],
    0.5,
    continuity=@edf.Plain,
  )
  assert_true(
    try {
      ignore(r.crop(1, 1))
      false
    } catch {
      _ => true
    },
  )
  let cropped = r.to_plus().crop(1, 1)
  assert_eq(cropped.starts, [0.5])
  assert_eq(cropped.digital(0, 0, 0), 2)
}

///|
test "TAL grammar UTF8 and trailing padding reject malformed input" {
  let good = b"+0\x14\x14\x00+1.5\x150.25\x14event\x14\x00\x00"
  let tals = @edf.parse_tals(good)
  assert_eq(tals.length(), 2)
  assert_eq(tals[1].duration, Some("0.25"))
  assert_eq(@edf.encode_tals(tals, good.length()), good)
  for
    bad in [
      b"0\x14\x14\x00", b"+0\x14bad\x00", b"+0\x14\xff\x14\x00", b"+0\x14\x14\x00\x00a",
      b"+0\x15-1\x14bad\x14\x00",
    ] {
    assert_true(
      try {
        ignore(@edf.parse_tals(bad))
        false
      } catch {
        _ => true
      },
    )
  }
}
