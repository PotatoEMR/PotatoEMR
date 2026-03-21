import fhir/r4us
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/element
import lustre/element/html as h

pub fn humannames_to_single_name_string(names: List(r4us.Humanname)) -> String {
  case names {
    [] -> "unnamed patient"
    [first_name, ..] -> humanname_to_string(first_name)
  }
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
              Some(s) -> s
              None -> "?"
            },
            " - ",
            case p.end {
              Some(e) -> e
              None -> "?"
            },
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

pub fn allergyintolerance_note_to_string(note) {
  "note todo"
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
  h.th([], [h.text(s)])
}

pub fn th_list(s) {
  s |> list.map(th)
}
