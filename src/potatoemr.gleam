// IMPORTS ---------------------------------------------------------------------

import fhir/r4
import fhir/r4_rsvp
import fhir/r4_sansio
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import rsvp

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(client: r4_rsvp.FhirClient, show: PatOrMsg)
}

type PatOrMsg {
  Pats(pats: List(r4.Patient))
  ErrMsg(err_msg: String)
  LoadingMsg
  EmptyMsg
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      show: EmptyMsg,
      client: r4_sansio.fhirclient_new("https://r4.smarthealthit.org"),
    )
  #(model, effect.none())
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ServerReturnedPatients(Result(List(r4.Patient), r4_rsvp.Err))
  UserTypedName(String)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ServerReturnedPatients(Ok(pats)) -> #(
      Model(..model, show: Pats(pats)),
      effect.none(),
    )
    ServerReturnedPatients(Error(err)) -> {
      let err_str = case err {
        r4_rsvp.ErrSansio(err) ->
          case err {
            r4_sansio.ErrNoId -> panic as "search doesnt need id"
            r4_sansio.ErrParseJson(err) ->
              "Error parsing json: " <> json_decode_error_to_string(err)
            r4_sansio.ErrNotJson(resp) -> resp.body
            r4_sansio.ErrOperationcome(oo) ->
              case oo.text {
                Some(txt) -> txt.div
                None -> {
                  oo.issue
                  |> list.map(fn(issue) {
                    "Issue: "
                    <> issue
                    |> r4.operationoutcome_issue_to_json
                    |> json.to_string
                  })
                  |> string.join("\n")
                }
              }
          }
        r4_rsvp.ErrRsvp(err) ->
          case err {
            rsvp.BadBody -> "Bad Body"
            rsvp.BadUrl(url) -> "Bad URL " <> url
            rsvp.HttpError(err) -> "Error: " <> err.body
            rsvp.JsonError(err) -> json_decode_error_to_string(err)
            rsvp.NetworkError -> "Network Error"
            rsvp.UnhandledResponse(err) -> "Unhandled Response: " <> err.body
          }
      }
      #(Model(..model, show: ErrMsg(err_str)), effect.none())
    }
    UserTypedName(name) ->
      case name {
        "" -> #(Model(..model, show: EmptyMsg), effect.none())
        name -> {
          let search: Effect(Msg) =
            r4_rsvp.patient_search(
              search_for: r4_sansio.SpPatient(
                ..r4_sansio.sp_patient_new(),
                name: Some(name),
              ),
              with_client: model.client,
              response_msg: ServerReturnedPatients,
            )
          let model = Model(..model, show: LoadingMsg)
          #(model, search)
        }
      }
  }
}

//copied from gloogle
pub fn json_decode_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "UnexpectedEndOfInput"
    json.UnexpectedByte(str) -> "UnexpectedByte " <> str
    json.UnexpectedSequence(str) -> "UnexpectedSequence " <> str
    json.UnableToDecode(errors) ->
      "UnableToDecode " <> print_decode_errors(errors)
  }
}

fn print_decode_errors(errors) {
  list.map(errors, fn(error) {
    let decode.DecodeError(expected:, found:, path:) = error
    "expected "
    <> expected
    <> " found "
    <> found
    <> " at "
    <> string.join(path, "/")
  })
  |> string.join("\n")
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  h.div(
    [
      a.style("border", "1px solid black"),
      a.style("height", "600px"),
      a.style("width", "90%"),
      a.style("margin", "auto"),
      a.style("overflow", "auto"),
      a.style("padding", "5px"),
    ],
    [
      h.input([
        a.placeholder("name"),
        event.debounce(event.on_input(UserTypedName), 200),
      ]),
      ..case model.show {
        EmptyMsg -> [element.none()]
        LoadingMsg -> [h.p([], [h.text("loading...")])]
        ErrMsg(err_str) -> [h.p([a.style("color", "red")], [h.text(err_str)])]
        Pats(pats) ->
          case pats {
            [] -> [h.p([], [h.text("no patients found")])]
            pats ->
              list.map(pats, fn(pat: r4.Patient) {
                h.p([], [
                  h.text(case pat.name {
                    [] ->
                      "unnamed patient"
                      <> case pat.id {
                        Some(id) -> " " <> id
                        None -> ""
                      }
                    names ->
                      list.map(names, fn(name) {
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
                            string.join(
                              [prefixes, given, family, suffixes, period],
                              " ",
                            )
                          }
                        }
                      })
                      |> string.join("\n")
                  }),
                ])
              })
          }
      }
    ],
  )
}
