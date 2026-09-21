///|
pub(all) struct DateTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
} derive(Debug, ToJson)

///|
fn month_days(year : Int, month : Int) -> Int {
  if month == 2 {
    if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
}

///|
fn DateTime::validate(self : DateTime) -> Unit raise EdfError {
  if self.year < 1985 ||
    self.year > 2084 ||
    self.month < 1 ||
    self.month > 12 ||
    self.day < 1 ||
    self.day > month_days(self.year, self.month) ||
    self.hour < 0 ||
    self.hour > 23 ||
    self.minute < 0 ||
    self.minute > 59 ||
    self.second < 0 ||
    self.second > 59 {
    raise Invalid("date/time outside supported Gregorian 1985..2084 range")
  }
}

///|
fn two(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
pub fn DateTime::date_field(self : DateTime) -> String raise EdfError {
  self.validate()
  "\{two(self.day)}.\{two(self.month)}.\{two(self.year%100)}"
}

///|
pub fn DateTime::time_field(self : DateTime) -> String raise EdfError {
  self.validate()
  "\{two(self.hour)}.\{two(self.minute)}.\{two(self.second)}"
}

///|
fn DateTime::long_date(self : DateTime) -> String {
  let months = [
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV",
    "DEC",
  ]
  "\{two(self.day)}-\{months[self.month-1]}-\{self.year}"
}

///|
pub fn parse_datetime(date : String, time : String) -> DateTime raise EdfError {
  if date.length() != 8 ||
    time.length() != 8 ||
    date[2] != '.' ||
    date[5] != '.' ||
    time[2] != '.' ||
    time[5] != '.' {
    raise Invalid("date/time must be dd.mm.yy and hh.mm.ss")
  }
  let yy = integer(date[6:8].to_owned())
  let dt : DateTime = {
    year: if yy >= 85 {
      1900 + yy
    } else {
      2000 + yy
    },
    month: integer(date[3:5].to_owned()),
    day: integer(date[0:2].to_owned()),
    hour: integer(time[0:2].to_owned()),
    minute: integer(time[3:5].to_owned()),
    second: integer(time[6:8].to_owned()),
  }
  dt.validate()
  dt
}

///|
pub fn DateTime::advance(
  self : DateTime,
  seconds : Int,
) -> DateTime raise EdfError {
  self.validate()
  if seconds < 0 {
    raise Invalid("calendar advance must be nonnegative")
  }
  let total = self.hour.to_int64() * 3600L +
    self.minute.to_int64() * 60L +
    self.second.to_int64() +
    seconds.to_int64()
  let mut days = (total / 86400L).to_int()
  let rest = (total % 86400L).to_int()
  let mut y = self.year
  let mut m = self.month
  let mut d = self.day
  while days > 0 {
    let left = month_days(y, m) - d
    if days <= left {
      d += days
      days = 0
    } else {
      days -= left + 1
      d = 1
      m += 1
      if m == 13 {
        m = 1
        y += 1
      }
      if y > 2084 {
        raise Limit("cropped date exceeds 2084")
      }
    }
  }
  {
    year: y,
    month: m,
    day: d,
    hour: rest / 3600,
    minute: rest % 3600 / 60,
    second: rest % 60,
  }
}
