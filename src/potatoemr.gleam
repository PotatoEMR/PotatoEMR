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
  // when user clicks a link in app, send msg to update fn
  let modem_effect =
    modem.init(fn(uri) { uri |> parse_route |> UserNavigatedTo })

  let assert Ok(client) =
    r4us_rsvp.fhirclient_new("https://r4.smarthealthit.org")

  let search =
    PatientSearch(
      text: "",
      visible: False,
      results: PatientSearchResultsEmptyMsg,
    )
  let model =
    Model(
      route: RouteNoId(Index),
      client:,
      search:,
      pat_id: None,
      patient_allergy: [],
    )
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
  Model(
    pat_id: Option(String),
    client: r4us_rsvp.FhirClient,
    search: PatientSearch,
    route: Route,
    patient_allergy: List(r4us.Allergyintolerance),
  )
}

type PatientSearch {
  PatientSearch(text: String, visible: Bool, results: PatientSearchResults)
}

type PatientSearchResults {
  PatientSearchResultsPats(pats: List(r4us.Patient))
  PatientSearchResultsErrMsg(err_msg: String)
  PatientSearchResultsLoadingMsg
  PatientSearchResultsEmptyMsg
}

type Visible {
  Show
  Hide
}

// routes, parse_route type -> uri
// must stay in sync with Route uri -> type
// and in sync with labels in view

type Route {
  RoutePatient(id: String, page: RoutePatientPage)
  RouteNoId(page: RouteNoId)
}

// while you could just stick these directly in route
// separating makes update easier to set model patient id
// without duplicating set id for each patient page
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
  NotFound(uri: Uri)
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
    RoutePatient(id:, page:) ->
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
        "overview" -> RoutePatient(id, PatientOverview)
        "allergies" -> RoutePatient(id, PatientAllergies)
        "medications" -> RoutePatient(id, PatientMedications)
        "vitals" -> RoutePatient(id, PatientVitals)
        _ -> RouteNoId(NotFound(uri:))
      }
    _ -> RouteNoId(NotFound(uri:))
  }
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserNavigatedTo(route: Route)
  UserFocusedSearch
  UserBlurredSearch
  UserSearchedPatient(String)
  ServerReturnedPatients(Result(List(r4us.Patient), r4us_rsvp.Err))
  ServerReturnedAllergies(Result(List(r4us.Allergyintolerance), r4us_rsvp.Err))
  ServerCreatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerUpdatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerDeletedAllergy(Result(r4us.Operationoutcome, r4us_rsvp.Err))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserNavigatedTo(route:) -> {
      let model = Model(..model, route:) |> set_search_visible(False)
      // currently closing search bar whenever changing page
      // might want to keep it open if not going to new patient, but would be a bit of work
      case route {
        RouteNoId(page) -> {
          let model = Model(..model, pat_id: None)
          case page {
            Index -> #(model, effect.none())
            Posts -> #(model, effect.none())
            About -> #(model, effect.none())
            NotFound(_) -> #(model, effect.none())
          }
        }
        RoutePatient(pat_id, page) -> {
          let model = Model(..model, pat_id: Some(pat_id))
          case page {
            PatientAllergies -> {
              let search_allergies: Effect(Msg) =
                r4us_rsvp.allergyintolerance_search(
                  search_for: r4us_sansio.SpAllergyintolerance(
                    ..r4us_sansio.sp_allergyintolerance_new(),
                    patient: Some("Patient/" <> pat_id),
                  ),
                  with_client: model.client,
                  response_msg: ServerReturnedAllergies,
                )
              #(Model(..model, patient_allergy: []), search_allergies)
            }
            // patient search -> click result navigates to overview
            // which sets current pat_id
            PatientOverview -> #(
              Model(..model, pat_id: Some(pat_id)),
              effect.none(),
            )
            PatientMedications -> #(model, effect.none())
            PatientVitals -> #(model, effect.none())
          }
        }
      }
    }
    UserSearchedPatient(name) ->
      case name {
        "" -> #(
          model |> set_search_result(PatientSearchResultsEmptyMsg),
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
              response_msg: ServerReturnedPatients,
            )
          let model = model |> set_search_result(PatientSearchResultsLoadingMsg)
          #(model, search)
        }
      }
    ServerReturnedPatients(Ok(pats)) -> #(
      model |> set_search_result(PatientSearchResultsPats(pats)),
      effect.none(),
    )
    ServerReturnedPatients(Error(_err)) -> {
      #(
        model |> set_search_result(PatientSearchResultsErrMsg("error")),
        effect.none(),
      )
    }
    UserFocusedSearch -> #(model |> set_search_visible(True), effect.none())
    UserBlurredSearch -> #(model |> set_search_visible(False), effect.none())
    ServerReturnedAllergies(Ok(patient_allergy)) -> #(
      Model(..model, patient_allergy:),
      effect.none(),
    )
    ServerReturnedAllergies(Error(_)) -> #(model, effect.none())
    ServerCreatedAllergy(Ok(allergy)) -> #(
      Model(..model, patient_allergy: [allergy, ..model.patient_allergy]),
      effect.none(),
    )
    ServerCreatedAllergy(Error(_)) -> todo
    ServerUpdatedAllergy(_) -> todo
    ServerDeletedAllergy(_) -> todo
  }
}

fn set_search_result(model: Model, results: PatientSearchResults) {
  Model(..model, search: PatientSearch(..model.search, results:))
}

fn set_search_visible(model: Model, visible: Bool) {
  Model(..model, search: PatientSearch(..model.search, visible:))
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  h.div([a.class("w-full h-full bg-slate-900 text-white")], [
    h.nav([a.class("flex justify-between items-center p-2 bg-slate-800")], [
      h.ul([a.class("flex space-x-4")], [
        h.input([
          a.placeholder("search name"),
          event.on_focus(UserFocusedSearch),
          event.on_blur(UserBlurredSearch),
          event.debounce(event.on_input(UserSearchedPatient), 200),
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
    ]),
    case model.search.visible {
      False -> element.none()
      True ->
        h.div(
          [
            a.class("absolute bg-zinc-800 w-lg h-80 overflow-auto"),
            event.prevent_default(event.on_mouse_down(UserFocusedSearch)),
          ],
          case model.search.results {
            PatientSearchResultsErrMsg(err_msg:) -> [
              h.p([a.class("red-300")], [h.text(err_msg)]),
            ]
            PatientSearchResultsLoadingMsg -> [h.text("loading...")]
            PatientSearchResultsEmptyMsg -> [h.text("empty")]
            PatientSearchResultsPats(pats:) ->
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
                            to: RoutePatient(id, PatientOverview),
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
    h.nav([a.class("flex justify-between items-center p-2 bg-slate-950")], [
      case model.pat_id {
        None -> element.none()
        Some(pat_id) ->
          h.ul([a.class("flex space-x-4")], [
            view_header_link(
              current: model.route,
              to: RoutePatient(pat_id, PatientOverview),
              label: "Overview",
            ),
            view_header_link(
              current: model.route,
              to: RoutePatient(pat_id, PatientAllergies),
              label: "Allergies",
            ),
            view_header_link(
              current: model.route,
              to: RoutePatient(pat_id, PatientMedications),
              label: "Medications",
            ),
            view_header_link(
              current: model.route,
              to: RoutePatient(pat_id, PatientVitals),
              label: "Vitals",
            ),
          ])
      },
    ]),
    h.main([a.class("my-16")], {
      case model.route {
        RouteNoId(page:) ->
          case page {
            Index -> view_index()
            Posts -> view_posts(model)
            About -> view_about()
            NotFound(uri) -> view_not_found(uri)
          }

        RoutePatient(_id, page:) ->
          case page {
            PatientOverview -> view_patient_overview(model)
            PatientAllergies -> view_patient_allergies(model)
            PatientMedications -> view_patient_medications(model)
            PatientVitals -> view_patient_vitals(model)
          }
      }
    }),
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

fn view_not_found(not_found: uri.Uri) -> List(Element(msg)) {
  h.p([], [h.text("404 not found: " <> uri.to_string(not_found))]) |> list.wrap
}

fn view_patient_overview(_model) -> List(Element(msg)) {
  [h.p([], [h.text("overview")])]
}

fn view_patient_allergies(model: Model) -> List(Element(msg)) {
  let head =
    h.tr(
      [],
      utils.th_list(["allergy", "criticality", "notes", "date_recorded"]),
    )
  let rows =
    list.map(model.patient_allergy, fn(allergy) {
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

fn view_patient_medications(_model) -> List(Element(msg)) {
  [h.p([], [h.text("meds")])]
}

fn view_patient_vitals(_model) -> List(Element(msg)) {
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
