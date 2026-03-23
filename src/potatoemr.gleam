import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri.{type Uri}
import lustre
import lustre/attribute.{type Attribute} as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import modem
import utils.{opt_elt}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_) -> #(Model, Effect(Msg)) {
  let assert Ok(client) =
    r4us_rsvp.fhirclient_new("https://r4.smarthealthit.org")

  // when user clicks a link in app, send msg to update fn
  let modem_effect =
    modem.init(fn(uri) { uri |> parse_route |> UserNavigatedTo })

  let search =
    SearchPatient(
      text: "",
      visible: False,
      results: SearchPatientResultsEmptyMsg,
    )
  let model = Model(route: RouteNoId(Index), client:, search:)

  // when someone comes from outside app to url, start at this route
  let route = case modem.initial_uri() {
    Ok(uri) -> parse_route(uri)
    Error(_) -> RouteNoId(Index)
  }
  // instead of just setting route in model we call update UserNavigatedTo(route)
  // to run the update case and get its effect msg
  // for example to make http request to search allergies for pat id abc123
  // when they navigate to /patient/abc123/allergies
  let #(model, firstload_effect) = update(model, UserNavigatedTo(route))

  #(model, effect.batch([modem_effect, firstload_effect]))
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(client: r4us_rsvp.FhirClient, search: SearchPatient, route: Route)
}

type SearchPatient {
  SearchPatient(text: String, visible: Bool, results: SearchPatientResults)
}

type SearchPatientResults {
  SearchPatientResultsPats(pats: List(r4us.Patient))
  SearchPatientResultsErrMsg(err_msg: String)
  SearchPatientResultsLoadingMsg
  SearchPatientResultsEmptyMsg
}

type Visible {
  Show
  Hide
}

// routes, parse_route type -> uri
// must stay in sync with Route uri -> type
// and in sync with labels in view

type Route {
  RoutePatient(id: String, patient: PatientLoad, page: RoutePatientPage)
  RouteNoId(page: RouteNoId)
}

type PatientLoad {
  PatientLoadStillLoading
  PatientLoadFound(data: PatientData)
  PatientLoadNotFound(String)
}

type PatientData {
  PatientData(
    patient: r4us.Patient,
    patient_allergies: List(r4us.Allergyintolerance),
    patient_medications: List(r4us.Medication),
    patient_observations: List(r4us.Observation),
  )
}

// while you could just stick these directly in route
// separating makes update easier to set model patient id
// without duplicating set id for each patient page
// plus guarantuee patient routes have a patient id
// a patient with that id existing is NOT guarantueed though
// model.patient is an option, might have a patient id that doesn't exist on server
// in which case show not found view
type RoutePatientPage {
  PatientOverview
  PatientAllergies
  PatientMedications
  PatientVitals
}

// similarly when update goes to these routes
// can easily set model.pat_id to None without duplication
type RouteNoId {
  Index
  Posts
  About
  NotFound(notfound: String)
}

fn href(route: Route) -> Attribute(msg) {
  let url = case route {
    RouteNoId(page:) ->
      case page {
        Index -> "/"
        About -> "/about"
        Posts -> "/posts"
        NotFound(_) -> "/404"
      }
    RoutePatient(_patient, id:, page:) ->
      case page {
        PatientOverview -> "/patient/" <> id <> "/overview"
        PatientAllergies -> "/patient/" <> id <> "/allergies"
        PatientMedications -> "/patient/" <> id <> "/medications"
        PatientVitals -> "/patient/" <> id <> "/vitals"
      }
  }
  a.href(url)
}

fn parse_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> RouteNoId(Index)
    ["posts"] -> RouteNoId(Posts)
    ["about"] -> RouteNoId(About)
    ["patient", id, page] ->
      case page {
        "overview" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientOverview,
          )
        "allergies" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientAllergies,
          )
        "medications" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientMedications,
          )
        "vitals" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientVitals,
          )
        _ -> uri |> uri.to_string |> NotFound |> RouteNoId
      }
    _ -> uri |> uri.to_string |> NotFound |> RouteNoId
  }
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserNavigatedTo(route: Route)
  UserFocusedSearch
  UserBlurredSearch
  UserSearchedPatient(String)
  ServerReturnedSearchPatients(Result(List(r4us.Patient), r4us_rsvp.Err))
  ServerReturnedPatientEverything(Result(r4us.Bundle, r4us_rsvp.Err))
  ServerCreatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerUpdatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerDeletedAllergy(Result(r4us.Operationoutcome, r4us_rsvp.Err))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserNavigatedTo(route:) -> {
      let #(model, effect) = case route {
        RouteNoId(_page) -> {
          let model = Model(..model, route:)
          #(model, effect.none())
        }
        RoutePatient(_page, _patient, id:) -> {
          // before getting all patient data, keep current patient data
          // so the sidebar and page will reload with new data if available
          // but will not blow away sidebar on every navigation while loading
          // instead keep patient from current route, and put in new route
          // at least until new patient data loads
          let existing_patient = case model.route {
            RouteNoId(_) -> PatientLoadStillLoading
            RoutePatient(existing_id, existing_patient, _existing_page) ->
              case id == existing_id {
                False -> PatientLoadStillLoading
                True -> existing_patient
              }
          }
          let route = RoutePatient(..route, patient: existing_patient)
          let model = Model(..model, route:)
          // send request to get all patient data
          // could do case on page here, but since we always do pateverything on load...
          // maybe don't need to do page case?
          // $everything might tax server? but good to stay in sync
          let pateverything: Effect(Msg) =
            r4us_rsvp.operation_any(
              params: None,
              operation_name: "everything",
              res_type: "Patient",
              res_id: Some(id),
              res_decoder: r4us.bundle_decoder(),
              client: model.client,
              handle_response: ServerReturnedPatientEverything,
            )
          #(model, pateverything)
        }
      }
      let model = model |> set_search_visible(False)
      // currently closing search bar whenever changing page
      // might want to keep it open if not going to new patient, but would be a bit of work
      #(model, effect)
    }
    UserSearchedPatient(name) ->
      case name {
        "" -> #(
          model |> set_search_result(SearchPatientResultsEmptyMsg),
          effect.none(),
        )
        name -> {
          let search: Effect(Msg) =
            r4us_rsvp.patient_search(
              search_for: r4us_sansio.SpPatient(
                ..r4us_sansio.sp_patient_new(),
                name: Some(name),
              ),
              with_client: model.client,
              response_msg: ServerReturnedSearchPatients,
            )
          let model = model |> set_search_result(SearchPatientResultsLoadingMsg)
          #(model, search)
        }
      }
    ServerReturnedSearchPatients(Ok(pats)) -> #(
      model |> set_search_result(SearchPatientResultsPats(pats)),
      effect.none(),
    )
    ServerReturnedSearchPatients(Error(_err)) -> {
      #(
        model |> set_search_result(SearchPatientResultsErrMsg("error")),
        effect.none(),
      )
    }
    UserFocusedSearch -> #(model |> set_search_visible(True), effect.none())
    UserBlurredSearch -> #(model |> set_search_visible(False), effect.none())
    ServerCreatedAllergy(Ok(allergy)) ->
      case model.route {
        RouteNoId(_) -> #(model, effect.none())
        RoutePatient(id:, page:, patient:) -> {
          let new_pat = case patient {
            PatientLoadFound(data:) -> {
              let patient_allergies = [allergy, ..data.patient_allergies]
              PatientLoadFound(PatientData(..data, patient_allergies:))
            }
            _ -> patient
          }
          #(
            Model(..model, route: RoutePatient(id:, page:, patient: new_pat)),
            effect.none(),
          )
        }
      }
    ServerCreatedAllergy(Error(_)) -> todo
    ServerUpdatedAllergy(_) -> todo
    ServerDeletedAllergy(_) -> todo
    ServerReturnedPatientEverything(Ok(pat_bundle)) -> {
      let resources = r4us_sansio.bundle_to_groupedresources(pat_bundle)
      let pat = case resources.patient {
        [] -> PatientLoadNotFound("no patient found")
        [first, ..] ->
          PatientLoadFound(PatientData(
            patient: first,
            patient_allergies: resources.allergyintolerance,
            patient_medications: resources.medication,
            patient_observations: resources.observation,
          ))
      }
      update_patient(model, fn(_oldpat) { pat })
    }
    ServerReturnedPatientEverything(Error(_)) ->
      update_patient(model, fn(_oldpat) {
        PatientLoadNotFound("error reading patient bundle")
      })
  }
}

fn set_search_result(model: Model, results: SearchPatientResults) {
  Model(..model, search: SearchPatient(..model.search, results:))
}

fn set_search_visible(model: Model, visible: Bool) {
  Model(..model, search: SearchPatient(..model.search, visible:))
}

fn update_patient_if_have_patient_already(
  model: Model,
  update_pat,
) -> #(Model, Effect(a)) {
  let update = fn(patient) {
    let new_pat = case patient {
      PatientLoadFound(data:) -> {
        let new_data = update_pat(data)
        PatientLoadFound(new_data)
      }
      _ -> patient
    }
  }
  update_patient(model, update)
}

fn update_patient(
  model: Model,
  update_pat: fn(PatientLoad) -> PatientLoad,
) -> #(Model, Effect(a)) {
  case model.route {
    RouteNoId(_) -> #(model, effect.none())
    RoutePatient(id:, page:, patient:) -> {
      let new_pat = update_pat(patient)
      #(
        Model(..model, route: RoutePatient(id:, page:, patient: new_pat)),
        effect.none(),
      )
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  h.div([a.class("w-full min-h-screen flex flex-col bg-slate-900 text-white")], [
    h.nav(
      [
        a.class(
          "flex justify-between p-2 bg-slate-800 border-b border-slate-700",
        ),
      ],
      [
        h.ul([a.class("flex space-x-4")], [
          h.li([a.class("relative")], [
            h.input([
              a.class("border border-slate-700"),
              a.placeholder("search name"),
              event.on_focus(UserFocusedSearch),
              event.on_blur(UserBlurredSearch),
              event.debounce(event.on_input(UserSearchedPatient), 200),
            ]),
            case model.search.visible {
              False -> element.none()
              True ->
                h.div(
                  [
                    a.class(
                      "absolute top-full left-0 bg-zinc-800 w-lg h-80 overflow-auto z-50",
                    ),
                    event.prevent_default(event.on_mouse_down(UserFocusedSearch)),
                  ],
                  case model.search.results {
                    SearchPatientResultsErrMsg(err_msg:) -> [
                      h.p([a.class("red-300")], [h.text(err_msg)]),
                    ]
                    SearchPatientResultsLoadingMsg -> [h.text("loading...")]
                    SearchPatientResultsEmptyMsg -> [h.text("empty")]
                    SearchPatientResultsPats(pats:) ->
                      case pats {
                        [] -> [h.p([], [h.text("no patients found")])]
                        pats ->
                          list.map(pats, fn(pat) {
                            h.p([], [
                              case pat.id {
                                None -> element.none()
                                Some(id) ->
                                  view_header_link(
                                    current: model.route,
                                    to: RoutePatient(
                                      id,
                                      PatientLoadStillLoading,
                                      PatientOverview,
                                    ),
                                    label: utils.humannames_to_single_name_string(
                                      pat.name,
                                    ),
                                  )
                              },
                            ])
                          })
                      }
                  },
                )
            },
          ]),
          view_header_link(
            current: model.route,
            to: RouteNoId(Index),
            label: "Home",
          ),
          view_header_link(
            current: model.route,
            to: RouteNoId(Posts),
            label: "Posts",
          ),
          view_header_link(
            current: model.route,
            to: RouteNoId(About),
            label: "About",
          ),
        ]),
      ],
    ),
    case model.route {
      RouteNoId(route) ->
        h.main([a.class("my-16 flex-1")], case route {
          Index -> view_index()
          Posts -> view_posts(model)
          About -> view_about()
          NotFound(not_found) -> view_not_found(not_found)
        })
      RoutePatient(id:, patient:, page:) ->
        h.main([a.class("flex flex-1")], [
          h.nav(
            [
              a.class("w-48 bg-slate-800 border-r border-slate-700"),
            ],
            case patient {
              PatientLoadStillLoading -> {
                [h.text("loading")]
              }
              PatientLoadNotFound(err) -> {
                [h.text("patient " <> id <> " not found: " <> err)]
              }
              PatientLoadFound(data:) -> {
                //let photo = model.pat.photo |> list.find_map(utils.get_img_src)
                [
                  h.img([a.src("abc"), a.alt("Patient Photo")]),
                  h.text("pat hi"),
                ]
              }
            },
          ),
          h.div([a.class("flex-1")], [
            h.ul(
              [
                a.class(
                  "p-2 flex space-x-4 bg-slate-800 border-b border-slate-700",
                ),
              ],
              [
                #(PatientOverview, "Overview"),
                #(PatientAllergies, "Allergies"),
                #(PatientMedications, "Medications"),
                #(PatientVitals, "Vitals"),
              ]
                |> list.map(fn(link) {
                  view_header_link(
                    current: model.route,
                    to: RoutePatient(id, PatientLoadStillLoading, link.0),
                    label: link.1,
                  )
                }),
            ),
            case patient {
              PatientLoadStillLoading -> {
                h.text("loading")
              }
              PatientLoadNotFound(err) -> {
                h.text("patient " <> id <> " not found: " <> err)
              }
              PatientLoadFound(data:) -> {
                h.div([], case page {
                  PatientOverview -> view_patient_overview(data)
                  PatientAllergies -> view_patient_allergies(data)
                  PatientMedications -> view_patient_medications(data)
                  PatientVitals -> view_patient_vitals(data)
                })
              }
            },
          ]),
        ])
    },
  ])
}

fn view_header_link(
  to target: Route,
  current current: Route,
  label text: String,
) -> Element(msg) {
  // let is_active = case current, target {
  //   PostById(_), Posts -> True
  //   _, _ -> current == target
  // }
  let is_active = current == target

  h.li(
    [
      a.classes([
        #("underline-offset-4", True),
        #("hover:underline", !is_active),
        #("underline", is_active),
      ]),
    ],
    [h.a([href(target)], [h.text(text)])],
  )
}

// VIEW PAGES ------------------------------------------------------------------

fn view_index() -> List(Element(msg)) {
  [
    title("Hello, Joe"),
    leading(
      "Or whoever you may be! This is were I will share random ramblings
       and thoughts about life.",
    ),
    h.p([a.class("mt-14")], [
      h.text("There is not much going on at the moment"),
    ]),
    paragraph("If you like <3"),
  ]
}

fn view_posts(model: Model) -> List(Element(msg)) {
  [h.p([], [h.text("hi")])]
}

fn view_about() -> List(Element(msg)) {
  [
    title("Me"),
    paragraph(
      "I document the odd occurrences that catch my attention and rewrite my own
       narrative along the way. I'm fine being referred to with pronouns.",
    ),
    paragraph(
      "If you enjoy these glimpses into my mind, feel free to come back
       semi-regularly. But not too regularly, you creep.",
    ),
  ]
}

fn view_not_found(not_found: String) {
  [h.p([], [h.text(not_found)])]
}

fn view_patient_overview(_model) {
  [h.p([], [h.text("overview")])]
}

fn view_patient_allergies(pat: PatientData) {
  let head =
    h.tr(
      [],
      utils.th_list(["allergy", "criticality", "notes", "date_recorded"]),
    )
  let rows =
    list.map(pat.patient_allergies, fn(allergy) {
      h.tr([], [
        h.td([], [
          case allergy.code {
            None -> element.none()
            Some(cc) -> h.p([], [h.text(utils.codeableconcept_to_string(cc))])
          },
        ]),
        h.td([], [
          case allergy.criticality {
            None -> element.none()
            Some(crit) ->
              h.p([], [
                h.text(r4us_valuesets.allergyintolerancecriticality_to_string(
                  crit,
                )),
              ])
          },
        ]),
        h.td([], [
          h.text(
            allergy.note
            |> list.map(utils.allergyintolerance_note_to_string)
            |> string.concat,
          ),
        ]),
        h.td([], [
          case allergy.recorded_date {
            None -> element.none()
            Some(rd) -> h.text(rd)
          },
        ]),
      ])
    })
  [
    h.div([], [h.text("create allergy")]),
    h.table([a.class("border-separate border-spacing-4")], [
      h.thead([], [head]),
      h.tbody([], rows),
    ]),
  ]
}

fn view_patient_medications(_model) {
  [h.p([], [h.text("meds")])]
}

fn view_patient_vitals(_model) {
  [h.p([], [h.text("vitals")])]
}

// VIEW HELPERS ----------------------------------------------------------------

fn title(title: String) -> Element(msg) {
  h.h2([a.class("text-3xl text-purple-800 font-light")], [
    h.text(title),
  ])
}

fn leading(text: String) -> Element(msg) {
  h.p([a.class("mt-8 text-lg")], [h.text(text)])
}

fn paragraph(text: String) -> Element(msg) {
  h.p([a.class("mt-14")], [h.text(text)])
}
