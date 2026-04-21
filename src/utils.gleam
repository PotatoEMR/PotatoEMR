import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/time/calendar as time_calendar
import gleam/time/duration
import gleam/time/timestamp
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import rsvp

pub fn err_to_string(err: r4us_rsvp.Err) {
  case err {
    r4us_rsvp.ErrRsvp(err:) -> rsvp_err_to_string(err)
    r4us_rsvp.ErrSansio(err:) -> sansio_err_to_string(err)
  }
}

pub fn rsvp_err_to_string(err: rsvp.Error) -> String {
  "http request error"
}

pub fn sansio_err_to_string(err: r4us_sansio.ErrResp) {
  case err {
    r4us_sansio.ErrParseJson(dec_err) ->
      "parsing json: "
      <> case dec_err {
        json.UnexpectedEndOfInput -> "unexpected end of input"
        json.UnexpectedByte(byte) -> "unexpected byte " <> byte
        json.UnexpectedSequence(seq) -> "unexpected sequence " <> seq
        json.UnableToDecode(dec_err) ->
          list.map(dec_err, fn(err) {
            string.concat([
              "expected ",
              err.expected,
              " but got ",
              err.found,
              " at ",
              string.join(err.path, "."),
            ])
          })
          |> string.join(",")
      }
    r4us_sansio.ErrNotJson(resp) ->
      "response not json: "
      <> int.to_string(resp.status)
      <> case resp.body {
        "" -> ""
        body -> " " <> body
      }
    r4us_sansio.ErrOperationoutcome(oo) -> oo |> operationoutcome_to_string
  }
}

fn operationoutcome_to_string(oo: r4us.Operationoutcome) -> String {
  let issues = [oo.issue.first, ..oo.issue.rest]
  issues
  |> list.map(fn(issue) {
    let path = case issue.expression {
      [_, ..] -> Some(string.join(issue.expression, ", "))
      [] ->
        case issue.location {
          [_, ..] -> Some(string.join(issue.location, ", "))
          [] -> None
        }
    }
    let details = option.map(issue.details, codeableconcept_to_string)
    [
      Some(r4us_valuesets.issueseverity_to_string(issue.severity)),
      Some(r4us_valuesets.issuetype_to_string(issue.code)),
      details,
      issue.diagnostics,
      path,
    ]
    |> option.values
    |> string.join(" ")
  })
  |> string.join("; ")
}

pub fn humannames_to_single_name_string(names: List(r4us.Humanname)) -> String {
  case
    names
    |> list.max(fn(name1, name2) {
      case name1.period, name2.period {
        Some(period1), Some(period2) ->
          case period1.start, period2.start {
            Some(start1), Some(start2) ->
              timestamp.compare(
                fhir_datetime_to_timestamp(start1),
                fhir_datetime_to_timestamp(start2),
              )
            Some(_), None -> order.Gt
            None, Some(_) -> order.Lt
            None, None -> order.Eq
          }
        Some(period1), None ->
          case period1.start {
            Some(_) -> order.Gt
            None -> order.Eq
          }
        None, Some(period2) ->
          case period2.start {
            Some(_) -> order.Lt
            None -> order.Eq
          }
        None, None -> order.Eq
      }
    })
  {
    Error(_) -> "unnamed patient"
    Ok(name) -> humanname_to_string(name)
  }
}

fn fhir_datetime_to_timestamp(dt: primitive_types.DateTime) {
  let primitive_types.DateTime(date, time) = dt
  let #(year, month, day) = case date {
    primitive_types.Year(year) -> #(year, time_calendar.January, 1)
    primitive_types.YearMonth(year, month) -> #(year, month, 1)
    primitive_types.YearMonthDay(year, month, day) -> #(year, month, day)
  }
  let #(time, offset) = case time {
    Some(primitive_types.TimeAndZone(time, zone)) -> #(time, case zone {
      primitive_types.Z -> time_calendar.utc_offset
      primitive_types.Offset(sign, hours, minutes) -> {
        let sign = case sign {
          primitive_types.Plus -> 1
          primitive_types.Minus -> -1
        }
        duration.add(
          duration.hours(hours * sign),
          duration.minutes(minutes * sign),
        )
      }
    })
    None -> #(primitive_types.Time(0, 0, 0, None), time_calendar.utc_offset)
  }
  let primitive_types.Time(hour, minute, second, nanosec) = time
  let nanosec = case nanosec {
    Some(primitive_types.NanosecWithPrecision(value, _)) -> value
    None -> 0
  }

  timestamp.from_calendar(
    date: time_calendar.Date(year, month, day),
    time: time_calendar.TimeOfDay(hour, minute, second, nanosec),
    offset: offset,
  )
}

pub fn humanname_to_string(name: r4us.Humanname) -> String {
  case name.text {
    Some(txt) -> txt
    None -> {
      let prefixes = name.prefix |> string.join(" ")
      let given = name.given |> string.join(" ")
      let family = case name.family {
        Some(f) -> f
        None -> ""
      }
      let suffixes = name.suffix |> string.join(" ")
      let period = case name.period {
        Some(p) ->
          string.concat([
            "(",
            case p.start {
              Some(s) -> s |> primitive_types.datetime_to_string
              None -> "?"
            },
            " - ",
            case p.end {
              Some(e) -> e |> primitive_types.datetime_to_string
              None -> "?"
            },
            ")",
          ])
        None -> ""
      }
      string.join([prefixes, given, family, suffixes, period], " ")
    }
  }
}

pub fn codeableconcept_to_string(cc: r4us.Codeableconcept) -> String {
  case cc.text {
    Some(txt) -> txt
    None -> cc.coding |> list.map(coding_to_string) |> string.concat
  }
}

pub fn coding_to_string(coding: r4us.Coding) -> String {
  case coding.display {
    Some(txt) -> txt
    None ->
      case coding.code {
        Some(txt) -> txt
        None -> "unnamed code"
      }
  }
}

pub fn annotation_first_text(note: List(r4us.Annotation)) {
  case note {
    [] -> ""
    [first, ..] -> first.text
  }
}

// like option.map except for optonal lustre element if not none
// case allergy.code {
//   None -> element.none()
//   Some(cc) -> h.p([], [h.text(utils.codeableconcept_to_string(cc))])
// }
// or something like this idk
pub fn opt_elt(
  from data: Option(a),
  with to_elt: fn(a) -> element.Element(b),
) -> element.Element(b) {
  case data {
    None -> element.none()
    Some(data) -> to_elt(data)
  }
}

pub fn th(s) {
  h.th([a.class("p-2 text-left")], [h.text(s)])
}

pub fn th_bordered(s) {
  h.th([a.class("p-2 text-left border border-slate-700")], [h.text(s)])
}

pub fn th_list(s) {
  s |> list.map(th)
}

pub fn get_img_src(img: r4us.Attachment) {
  case img.url {
    Some(url) -> Ok(url)
    None ->
      case img.data, img.content_type {
        Some(data), Some(ctype) -> Ok("data:" <> ctype <> ";base64," <> data)
        _, _ -> Error(Nil)
      }
  }
}

pub fn patient_to_reference(res: r4us.Patient) {
  let reference = case res.id {
    Some(id) -> Some("Patient/" <> id)
    None -> None
  }
  let type_ = Some("Patient")
  let identifier = case res.identifier {
    [] -> None
    [first, ..] -> Some(first)
  }
  //pat to string todo
  let display = None
  r4us.Reference(
    id: None,
    extension: [],
    reference:,
    type_:,
    identifier:,
    display:,
  )
}

pub fn coding(code code: String, system system: String, display display: String) {
  r4us.Coding(
    ..r4us.coding_new(),
    code: Some(code),
    system: Some(system),
    display: Some(display),
  )
}

pub fn view_patient_photo_box(src, click_effect) {
  let attrs = [
    a.src(src),
    a.alt("Patient Photo"),
    a.class(
      "w-48 h-48 object-cover rounded-full hover:opacity-50 transition-opacity cursor-pointer text-center leading-[12rem]",
    ),
    a.attribute("draggable", "false"),
  ]
  let attrs = case click_effect {
    Some(click_effect) -> [click_effect, ..attrs]
    None -> attrs
  }
  h.img(attrs)
}
