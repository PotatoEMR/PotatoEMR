import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, type Msg, type Route, Model, href} as mm
import modem
import pages/general/index
import pages/general/notfound
import pages/general/registerpatient
import pages/general/settings
import pages/patient/allergy
import pages/patient/medication
import pages/patient/overview
import pages/patient/photo
import pages/patient/vitals
import utils
import utils2

const patient_photo_placeholder = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='150' height='150' viewBox='0 0 150 150'%3E%3Cpath fill='%23ccc' d='M 104.68731,56.689353 C 102.19435,80.640493 93.104981,97.26875 74.372196,97.26875 55.639402,97.26875 46.988823,82.308034 44.057005,57.289941 41.623314,34.938838 55.639402,15.800152 74.372196,15.800152 c 18.732785,0 32.451944,18.493971 30.315114,40.889201 z'/%3E%3Cpath fill='%23ccc' d='M 92.5675 89.6048 C 90.79484 93.47893 89.39893 102.4504 94.86478 106.9039 C 103.9375 114.2963 106.7064 116.4723 118.3117 118.9462 C 144.0432 124.4314 141.6492 138.1543 146.5244 149.2206 L 4.268444 149.1023 C 8.472223 138.6518 6.505799 124.7812 32.40051 118.387 C 41.80992 116.0635 45.66513 113.8823 53.58659 107.0158 C 58.52744 102.7329 57.52583 93.99267 56.43084 89.26926 C 52.49275 88.83011 94.1739 88.14054 92.5675 89.6048 z'/%3E%3C/svg%3E"

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_) -> #(Model, Effect(Msg)) {
  let assert Ok(client) =
    r4us_rsvp.fhirclient_new("https://r4.smarthealthit.org/")

  // when user clicks a link in app, send msg to update fn
  let modem_effect =
    modem.init(fn(uri) { uri |> mm.uri_to_route |> mm.UserNavigatedTo })

  let search =
    mm.SearchPatient(
      text: "",
      visible: False,
      results: mm.SearchPatientResultsEmptyMsg,
    )
  let model =
    Model(
      route: mm.RouteNoId(mm.Index),
      client:,
      search:,
      dragging_photo: False,
    )

  // when someone comes from outside app to url, start at this route
  let route = case modem.initial_uri() {
    Ok(uri) -> mm.uri_to_route(uri)
    Error(_) -> mm.RouteNoId(mm.Index)
  }
  // instead of just setting route in model we call update UserNavigatedTo(route)
  // to run the update case and get its effect msg
  // for example to make http request to search allergies for pat id abc123
  // when they navigate to /patient/abc123/allergies
  let #(model, firstload_effect) = update(model, mm.UserNavigatedTo(route))

  let dropzone_effect =
    effect.from(fn(dispatch) {
      utils2.setup_body_dropzone(
        fn(dragging) { dispatch(mm.UserDraggingPhoto(dragging)) },
        fn(data_url) { dispatch(mm.UserSelectedPhotoDataUrl(data_url)) },
      )
    })

  #(model, effect.batch([modem_effect, firstload_effect, dropzone_effect]))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    mm.UserNavigatedTo(route:) -> {
      let #(model, effect) = case route {
        mm.RouteNoId(_page) -> {
          let model = Model(..model, route:)
          #(model, effect.none())
        }
        mm.RoutePatient(_page, _patient, id:) -> {
          // before getting all patient data, keep current patient data
          // so the sidebar and page will reload with new data if available
          // but will not blow away sidebar on every navigation while loading
          // instead keep patient from current route, and put in new route
          // at least until new patient data loads
          let existing_patient = case model.route {
            mm.RouteNoId(_) -> mm.PatientLoadStillLoading
            mm.RoutePatient(existing_id, existing_patient, _existing_page) ->
              case id == existing_id {
                False -> mm.PatientLoadStillLoading
                True -> existing_patient
              }
          }
          let route = mm.RoutePatient(..route, patient: existing_patient)
          let model = Model(..model, route:)
          // send request to get all patient data
          // could do case on page here, but since we always do pateverything on load...
          // maybe don't need to do page case?
          // $everything might tax server? but good to stay in sync

          // let pateverything: Effect(Msg) =
          //   r4us_rsvp.operation_any(
          //     params: None,
          //     operation_name: "everything",
          //     res_type: "Patient",
          //     res_id: Some(id),
          //     res_decoder: r4us.bundle_decoder(),
          //     client: model.client,
          //     handle_response: ServerReturnedPatientEverything,
          //   )

          // a) not every server supports patient$everything
          // b) everything returns bundle with resources we don't use,
          // which wouldn't be the end of the world, except if they fail
          // to decode, currently the whole bundle fails to decode
          let pateverything =
            r4us_rsvp.search_any(
              "_id="
                <> id
                <> "&_revinclude=AllergyIntolerance:patient&_revinclude=MedicationRequest:patient&_revinclude=MedicationStatement:patient&_revinclude=Observation:patient&_revinclude=Condition:patient&_revinclude=Encounter:patient",
              "Patient",
              model.client,
              mm.ServerReturnedPatientEverything,
            )
          #(model, pateverything)
        }
      }
      let model = model |> set_search_visible(False)
      // currently closing search bar whenever changing page
      // might want to keep it open if not going to new patient, but would be a bit of work
      #(model, effect)
    }

    mm.UserSearchedPatient(name) ->
      case name {
        "" -> #(
          model |> set_search_result(mm.SearchPatientResultsEmptyMsg),
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
              response_msg: mm.ServerReturnedSearchPatients,
            )
          let model =
            model
            |> set_search_result(mm.SearchPatientResultsLoadingMsg)
            |> set_search_visible(True)
          #(model, search)
        }
      }
    mm.ServerReturnedSearchPatients(Ok(pats)) -> #(
      model |> set_search_result(mm.SearchPatientResultsPats(pats)),
      effect.none(),
    )
    mm.ServerReturnedSearchPatients(Error(_err)) -> {
      #(
        model |> set_search_result(mm.SearchPatientResultsErrMsg("error")),
        effect.none(),
      )
    }
    mm.UserFocusedSearch -> #(model |> set_search_visible(True), effect.none())
    mm.UserBlurredSearch -> #(model |> set_search_visible(False), effect.none())
    mm.ServerReturnedPatientEverything(Ok(pat_bundle)) -> {
      let resources = r4us_sansio.bundle_to_groupedresources(pat_bundle)
      let pat = case resources.patient {
        [] -> mm.PatientLoadNotFound("no patient found")
        [first, ..] ->
          mm.PatientLoadFound(mm.PatientData(
            patient: first,
            patient_allergies: resources.allergyintolerance,
            patient_medications: resources.medication,
            patient_observations: resources.observation,
          ))
      }
      utils2.update_patient(model, fn(_oldpat) { pat })
    }
    mm.ServerReturnedPatientEverything(Error(err)) ->
      utils2.update_patient(model, fn(_oldpat) {
        echo err
        mm.PatientLoadNotFound("error reading patient bundle")
      })
    mm.UserClickedChangeClient(baseurl) ->
      settings.switch_client(model, baseurl)
    mm.ServerUpdatedPatientPhoto(Error(err)) -> todo
    mm.UserDraggingPhoto(dragging_photo) ->
      photo.set_drag_photo(model, dragging_photo)
    mm.UserSelectedPhotoEvent(event) -> photo.select_photo(model, event)
    mm.UserSelectedPhotoDataUrl(dataurl) -> photo.select_daturl(model, dataurl)
    mm.UserClickedExistingPhoto(num) -> photo.set_existing(model, num)
    mm.ServerUpdatedPatientPhoto(Ok(patient)) -> photo.update(model, patient)
    mm.ServerCreatedAllergy(Ok(alrgy)) -> allergy.server_created(model, alrgy)
    mm.ServerCreatedAllergy(Error(_)) -> todo
    mm.ServerUpdatedAllergy(Ok(alrgy)) -> allergy.server_updated(model, alrgy)
    mm.ServerUpdatedAllergy(Error(_)) -> todo
    mm.ServerDeletedAllergy(_) -> todo
    mm.UserClickedCreateAllergy -> allergy.edit(model, None)
    mm.UserClickedEditAllergy(id) -> allergy.edit(model, Some(id))
    mm.UserClickedCloseAllergyForm -> allergy.close_form(model)
    mm.UserSubmittedAllergyForm(Ok(new_allergy)) ->
      allergy.submit(model, new_allergy)
    mm.UserSubmittedAllergyForm(Error(err)) -> allergy.form_errors(model, err)
    mm.UserClickedRegisterPatient(Ok(newpat)) ->
      registerpatient.create(model, newpat)
    mm.UserClickedRegisterPatient(Error(err)) ->
      registerpatient.form_errors(model, err)
    mm.ServerReturnedRegisterPatient(Ok(created_pat)) ->
      registerpatient.created(model, created_pat)
    mm.ServerReturnedRegisterPatient(Error(err)) ->
      registerpatient.create_error(model, err)
  }
}

fn set_search_result(model: Model, results: mm.SearchPatientResults) {
  Model(..model, search: mm.SearchPatient(..model.search, results:))
}

fn set_search_visible(model: Model, visible: Bool) {
  Model(..model, search: mm.SearchPatient(..model.search, visible:))
}

// VIEW ------------------------------------------------------------------------

const nav_bar_class = "flex items-end space-x-1 px-2 h-10 bg-slate-800 border-b border-slate-700"

fn view(model: Model) -> Element(Msg) {
  h.div([a.class("w-full min-h-screen flex flex-col bg-slate-900 text-white")], [
    h.nav([a.class(nav_bar_class)], [
      h.div([a.class("relative")], [
        h.input([
          a.class(
            "w-lg h-8 m-1 pl-4 rounded-full border border-slate-700 bg-slate-950 focus:outline focus:outline-purple-600",
          ),
          a.placeholder("⌕ search patient name"),
          event.on_focus(mm.UserFocusedSearch),
          event.on_blur(mm.UserBlurredSearch),
          event.debounce(event.on_input(mm.UserSearchedPatient), 200),
        ]),
        case model.search.visible {
          False -> element.none()
          True ->
            h.div(
              [
                a.class(
                  "absolute top-full left-0 -mt-1 bg-slate-800 border border-slate-700 w-3xl h-120 overflow-auto z-50",
                ),
                event.prevent_default(event.on_mouse_down(mm.UserFocusedSearch)),
              ],
              case model.search.results {
                mm.SearchPatientResultsErrMsg(err_msg:) -> [
                  h.p([a.class("red-300")], [h.text(err_msg)]),
                ]
                mm.SearchPatientResultsLoadingMsg -> [h.text("loading...")]
                mm.SearchPatientResultsEmptyMsg -> [h.text("empty")]
                mm.SearchPatientResultsPats(pats:) ->
                  case pats {
                    [] -> [h.p([], [h.text("no patients found")])]
                    pats ->
                      list.map(pats, fn(pat) {
                        case pat.id {
                          None -> element.none()
                          Some(id) -> {
                            let photo_src =
                              pat.photo
                              |> list.find_map(utils.get_img_src)
                              |> result.unwrap(patient_photo_placeholder)
                            let name =
                              utils.humannames_to_single_name_string(pat.name)
                            let gender = case pat.gender {
                              None -> ""
                              Some(g) ->
                                r4us_valuesets.administrativegender_to_string(g)
                            }
                            let age = case pat.birth_date {
                              None -> ""
                              Some(bd) -> bd
                            }
                            let identifier = case pat.identifier {
                              [] -> ""
                              [first, ..] -> option.unwrap(first.value, "")
                            }
                            let detail =
                              [gender, age, identifier]
                              |> list.filter(fn(s) { s != "" })
                              |> string.join(" \u{00B7} ")
                            h.a(
                              [
                                href(mm.RoutePatient(
                                  id,
                                  mm.PatientLoadStillLoading,
                                  mm.PatientOverview,
                                )),
                                a.class(
                                  "flex items-center gap-3 p-4 hover:bg-slate-900",
                                ),
                              ],
                              [
                                h.img([
                                  a.src(photo_src),
                                  a.class("w-20 h-20 rounded-full object-cover"),
                                ]),
                                h.div([], [
                                  h.p([a.class("font-bold")], [
                                    h.text(name),
                                  ]),
                                  h.p([a.class("text-sm text-slate-400")], [
                                    h.text(detail),
                                  ]),
                                ]),
                              ],
                            )
                          }
                        }
                      })
                  }
              },
            )
        },
      ]),
      ..view_header_links(
        [
          #(mm.Index, "Home"),
          #(mm.Settings, "Settings"),
          #(mm.RegisterPatient(None), "Register New Patient"),
        ],
        current: model.route,
      )
    ]),
    case model.route {
      mm.RouteNoId(route) ->
        h.main([a.class("my-16 flex-1")], case route {
          mm.Index -> index.view()
          mm.Settings -> settings.view(model)
          mm.RegisterPatient(newpatient) -> registerpatient.view(newpatient)
          mm.NotFound(not_found) -> notfound.view(not_found)
        })
      mm.RoutePatient(id:, patient:, page:) ->
        h.main([a.class("flex flex-1")], [
          h.nav(
            [
              a.class(
                "w-56 shrink-0 bg-slate-800 border-r border-slate-700 flex flex-col items-center p-2",
              ),
            ],
            case patient {
              mm.PatientLoadStillLoading -> {
                [h.text("loading")]
              }
              mm.PatientLoadNotFound(err) -> {
                [h.text("patient " <> id <> " not found: " <> err)]
              }
              mm.PatientLoadFound(data:) -> {
                let photo =
                  data.patient.photo
                  |> list.find_map(utils.get_img_src)
                  |> result.unwrap(patient_photo_placeholder)
                  |> utils.view_patient_photo_box(None)
                // view_patient_photo_box takes Msg to run on click
                // but here we navigate with href/modem instead, and pass None in for msg
                [
                  h.a(
                    [
                      href(mm.RoutePatient(
                        id:,
                        patient:,
                        page: mm.PatientPhotos,
                      )),
                    ],
                    [photo],
                  ),
                  h.text(
                    patient.data.patient.name
                    |> utils.humannames_to_single_name_string,
                  ),
                ]
              }
            },
          ),
          h.div([a.class("flex-1")], [
            h.ul(
              [a.class(nav_bar_class)],
              [
                #(mm.PatientOverview, "Overview"),
                #(mm.PatientAllergies(mm.FormStateNone), "Allergies"),
                #(mm.PatientMedications, "Medications"),
                #(mm.PatientVitals, "Vitals"),
              ]
                |> list.map(fn(link) {
                  view_header_link(
                    current: model.route,
                    to: mm.RoutePatient(id, mm.PatientLoadStillLoading, link.0),
                    label: link.1,
                  )
                }),
            ),
            case patient {
              mm.PatientLoadStillLoading -> {
                h.text("loading")
              }
              mm.PatientLoadNotFound(_) -> {
                h.text("loading")
              }
              mm.PatientLoadFound(data:) -> {
                h.div([], case page {
                  mm.PatientOverview -> overview.view(data)
                  mm.PatientAllergies(allergy_form) ->
                    allergy.view(data, allergy_form)
                  mm.PatientMedications -> medication.view(data)
                  mm.PatientVitals -> vitals.view(data)
                  mm.PatientPhotos -> photo.view(model, data)
                })
              }
            },
          ]),
        ])
    },
  ])
}

fn view_header_links(
  current current,
  to targets_and_displays: List(#(mm.RouteNoId, String)),
) {
  list.map(targets_and_displays, fn(link) {
    view_header_link(to: mm.RouteNoId(link.0), current:, label: link.1)
  })
}

fn view_header_link(
  to target: Route,
  current current: Route,
  label text: String,
) -> Element(msg) {
  let active = mm.route_to_urlstring(current) == mm.route_to_urlstring(target)

  h.li([a.class("flex -mb-px")], [
    h.a(
      [
        href(target),
        a.classes([
          #("flex items-center px-3 py-1 rounded-t-2xl border-x border-t", True),
          #("hover:text-slate-300 border-transparent", !active),
          #("bg-[#0f172b] border-slate-700", active),
        ]),
      ],
      [h.text(text)],
    ),
  ])
}
