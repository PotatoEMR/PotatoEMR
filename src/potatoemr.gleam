import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import lustre
import lustre/attribute.{type Attribute} as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/svg
import lustre/event
import modem
import utils.{opt_elt}

const patient_photo_placeholder = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='150' height='150' viewBox='0 0 150 150'%3E%3Cpath fill='%23ccc' d='M 104.68731,56.689353 C 102.19435,80.640493 93.104981,97.26875 74.372196,97.26875 55.639402,97.26875 46.988823,82.308034 44.057005,57.289941 41.623314,34.938838 55.639402,15.800152 74.372196,15.800152 c 18.732785,0 32.451944,18.493971 30.315114,40.889201 z'/%3E%3Cpath fill='%23ccc' d='M 92.5675 89.6048 C 90.79484 93.47893 89.39893 102.4504 94.86478 106.9039 C 103.9375 114.2963 106.7064 116.4723 118.3117 118.9462 C 144.0432 124.4314 141.6492 138.1543 146.5244 149.2206 L 4.268444 149.1023 C 8.472223 138.6518 6.505799 124.7812 32.40051 118.387 C 41.80992 116.0635 45.66513 113.8823 53.58659 107.0158 C 58.52744 102.7329 57.52583 93.99267 56.43084 89.26926 C 52.49275 88.83011 94.1739 88.14054 92.5675 89.6048 z'/%3E%3C/svg%3E"

@external(javascript, "./potatoemr_ffi.mjs", "read_file_from_event")
fn read_file_from_event(
  event: dynamic.Dynamic,
  callback: fn(String) -> Nil,
) -> Nil

@external(javascript, "./potatoemr_ffi.mjs", "setup_body_dropzone")
fn setup_body_dropzone(
  on_drag: fn(Bool) -> Nil,
  on_drop_file: fn(String) -> Nil,
) -> Nil

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
  let model =
    Model(route: RouteNoId(Index), client:, search:, dragging_photo: False)

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

  let dropzone_effect =
    effect.from(fn(dispatch) {
      setup_body_dropzone(
        fn(dragging) { dispatch(UserDraggingPhoto(dragging)) },
        fn(data_url) { dispatch(UserSelectedPhotoDataUrl(data_url)) },
      )
    })

  #(model, effect.batch([modem_effect, firstload_effect, dropzone_effect]))
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    client: r4us_rsvp.FhirClient,
    search: SearchPatient,
    route: Route,
    dragging_photo: Bool,
  )
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
    patient_allergy_new: r4us.Allergyintolerance,
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
  PatientPhotos
}

// similarly when update goes to these routes
// can easily set model.pat_id to None without duplication
type RouteNoId {
  Index
  Posts
  Settings
  NotFound(notfound: String)
}

fn href(route: Route) -> Attribute(msg) {
  let url = case route {
    RouteNoId(page:) ->
      case page {
        Index -> "/"
        Settings -> "/settings"
        Posts -> "/posts"
        NotFound(_) -> "/404"
      }
    RoutePatient(_patient, id:, page:) ->
      case page {
        PatientOverview -> "/patient/" <> id <> "/overview"
        PatientAllergies -> "/patient/" <> id <> "/allergies"
        PatientMedications -> "/patient/" <> id <> "/medications"
        PatientVitals -> "/patient/" <> id <> "/vitals"
        PatientPhotos -> "/patient/" <> id <> "/photos"
      }
  }
  a.href(url)
}

fn parse_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> RouteNoId(Index)
    ["posts"] -> RouteNoId(Posts)
    ["settings"] -> RouteNoId(Settings)
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
        "photos" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientPhotos,
          )
        _ -> uri |> uri.to_string |> NotFound |> RouteNoId
      }
    _ -> uri |> uri.to_string |> NotFound |> RouteNoId
  }
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserNavigatedTo(route: Route)
  UserClickedChangeClient(String)
  UserFocusedSearch
  UserBlurredSearch
  UserSearchedPatient(String)
  ServerReturnedSearchPatients(Result(List(r4us.Patient), r4us_rsvp.Err))
  ServerReturnedPatientEverything(Result(r4us.Bundle, r4us_rsvp.Err))
  ServerCreatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerUpdatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerDeletedAllergy(Result(r4us.Operationoutcome, r4us_rsvp.Err))
  ServerUpdatedPatientPhoto(Result(r4us.Patient, r4us_rsvp.Err))
  UserTypedAllergyintoleranceNote(input: String, on_id: Option(String))
  UserClickedCreateAllergy
  UserSelectedPhotoEvent(dynamic.Dynamic)
  UserSelectedPhotoDataUrl(String)
  UserDraggingPhoto(Bool)
  UserClickedExistingPhoto(Int)
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
              ServerReturnedPatientEverything,
            )
          #(model, pateverything)
        }
      }
      let model = model |> set_search_visible(False)
      // currently closing search bar whenever changing page
      // might want to keep it open if not going to new patient, but would be a bit of work
      #(model, effect)
    }
    UserClickedChangeClient(baseurl) -> {
      let client = r4us_rsvp.fhirclient_new(baseurl)
      case client {
        Ok(client) -> #(Model(..model, client:), effect.none())
        Error(_) -> #(model, effect.none())
      }
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
            patient_allergy_new: r4us.allergyintolerance_new(
              utils.patient_to_reference(first),
            ),
            patient_allergies: resources.allergyintolerance,
            patient_medications: resources.medication,
            patient_observations: resources.observation,
          ))
      }
      update_patient(model, fn(_oldpat) { pat })
    }
    ServerReturnedPatientEverything(Error(err)) ->
      update_patient(model, fn(_oldpat) {
        echo err
        PatientLoadNotFound("error reading patient bundle")
      })
    ServerUpdatedPatientPhoto(Ok(patient)) ->
      update_patient(model, fn(pat) {
        case pat {
          PatientLoadFound(data:) ->
            PatientLoadFound(PatientData(..data, patient:))
          _ -> pat
          // in _ case could creeate new patient data, but would be weird to be in that case
        }
      })
    ServerUpdatedPatientPhoto(Error(err)) -> todo
    UserDraggingPhoto(dragging_photo) ->
      case model.route {
        RoutePatient(page: PatientPhotos, ..) -> #(
          Model(..model, dragging_photo:),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    UserSelectedPhotoEvent(event) -> #(
      Model(..model, dragging_photo: False),
      effect.from(fn(dispatch) {
        read_file_from_event(event, fn(data_url) {
          dispatch(UserSelectedPhotoDataUrl(data_url))
        })
      }),
    )
    UserSelectedPhotoDataUrl(data_url) -> {
      // data_url is like "data:image/png;base64,iVBOR..."
      // split into content_type and base64 data for FHIR Attachment
      case model.route {
        RoutePatient(id:, page:, patient:) ->
          case patient {
            PatientLoadFound(data:) -> {
              let #(content_type, base64) = parse_data_url(data_url)
              let new_photo =
                r4us.Attachment(
                  ..r4us.attachment_new(),
                  content_type: Some(content_type),
                  data: Some(base64),
                )
              let newpat =
                r4us.Patient(..data.patient, photo: [
                  new_photo,
                  ..data.patient.photo
                ])
              let effect =
                newpat
                |> r4us_rsvp.patient_update(
                  model.client,
                  ServerUpdatedPatientPhoto,
                )
                |> result.unwrap(effect.none())
              // don't *have* to update model patient photo here
              // as the server response msg will update model
              // but if we do it here too the user gets instant feedback
              let newdata = PatientData(..data, patient: newpat)
              let patient = PatientLoadFound(newdata)
              let model =
                Model(..model, route: RoutePatient(id:, page:, patient:))
              #(model, effect)
            }
            _ -> #(model, effect.none())
          }
        _ -> #(model, effect.none())
      }
    }
    UserClickedExistingPhoto(num) -> {
      case model.route {
        RoutePatient(id:, page:, patient:) ->
          case patient {
            PatientLoadFound(data:) -> {
              case data.patient.photo {
                [] -> todo
                [first, ..] -> {
                  // indicating use this picture by moving to front of list
                  // is not that short but not terrible
                  // but idk if json guarantueed to keep order on server
                  // might be better to indicate chosen profile pic another way
                  let #(move_to_front, photos) =
                    list.index_fold(
                      over: data.patient.photo,
                      from: #(first, []),
                      with: fn(acc, existing_photo, idx) {
                        case idx == num {
                          True -> #(existing_photo, acc.1)
                          False -> #(acc.0, [existing_photo, ..acc.1])
                        }
                      },
                    )
                  let photos = list.reverse(photos)
                  let photos = [move_to_front, ..photos]
                  let newpat = r4us.Patient(..data.patient, photo: photos)
                  let newdata = PatientData(..data, patient: newpat)
                  let patient = PatientLoadFound(newdata)
                  let effect =
                    newpat
                    |> r4us_rsvp.patient_update(
                      model.client,
                      ServerUpdatedPatientPhoto,
                    )
                    |> result.unwrap(effect.none())
                  let model =
                    Model(..model, route: RoutePatient(id:, page:, patient:))
                  #(model, effect)
                }
              }
            }
            _ -> #(model, effect.none())
          }
        _ -> #(model, effect.none())
      }
    }
    UserTypedAllergyintoleranceNote(input:, on_id:) ->
      if_pat_data_update_patient(model, fn(data) {
        case on_id {
          None -> {
            let new_note = case data.patient_allergy_new.note {
              [] -> [r4us.annotation_new(input)]
              [note] -> [r4us.Annotation(..note, text: input)]
              [note, ..rest] -> [r4us.Annotation(..note, text: input), ..rest]
            }
            let new_allergy =
              r4us.Allergyintolerance(
                ..data.patient_allergy_new,
                note: new_note,
              )
            PatientData(..data, patient_allergy_new: new_allergy)
          }
          Some(_) -> {
            let on_allergy =
              list.find(data.patient_allergies, fn(allergy) {
                allergy.id == on_id
              })
            case on_allergy {
              // strange case if existing allergy has no id to identify it in list
              Error(_) -> data
              Ok(on_allergy) -> {
                let allergy_rest =
                  list.filter(data.patient_allergies, fn(allergy) {
                    allergy.id != on_id
                  })
                let new_note = case on_allergy.note {
                  [] -> [r4us.annotation_new(input)]
                  [note] -> [r4us.Annotation(..note, text: input)]
                  [note, ..note_rest] -> [
                    r4us.Annotation(..note, text: input),
                    ..note_rest
                  ]
                }
                let new_allergy = [
                  r4us.Allergyintolerance(..on_allergy, note: new_note),
                  ..allergy_rest
                ]
                PatientData(..data, patient_allergies: new_allergy)
              }
            }
          }
        }
      })
    UserClickedCreateAllergy -> {
      case model.route {
        RouteNoId(page:) -> #(model, effect.none())
        RoutePatient(id:, patient:, page:) ->
          case patient {
            PatientLoadFound(data) -> {
              let effect =
                r4us_rsvp.allergyintolerance_create(
                  data.patient_allergy_new,
                  model.client,
                  ServerCreatedAllergy,
                )
              #(model, effect)
            }
            _ -> #(model, effect.none())
          }
      }
    }
  }
}

fn send_model_pat_to_server(model: Model) {
  todo
}

fn set_search_result(model: Model, results: SearchPatientResults) {
  Model(..model, search: SearchPatient(..model.search, results:))
}

fn set_search_visible(model: Model, visible: Bool) {
  Model(..model, search: SearchPatient(..model.search, visible:))
}

// if model doesnt have patient when trying to update patient data (weird?), don't do anything
// could maybe use the other update_patient fn but want to be able to send effect
fn if_pat_data_update_patient(
  model: Model,
  update_pat: fn(PatientData) -> PatientData,
) -> #(Model, Effect(a)) {
  case model.route {
    RouteNoId(_) -> #(model, effect.none())
    RoutePatient(id:, page:, patient:) -> {
      case patient {
        PatientLoadFound(data:) -> {
          let newpatient = PatientLoadFound(update_pat(data))
          let model =
            Model(..model, route: RoutePatient(id:, page:, patient: newpatient))
          #(model, effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
  }
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

fn parse_data_url(data_url: String) -> #(String, String) {
  // "data:image/png;base64,iVBOR..." -> #("image/png", "iVBOR...")
  case string.split_once(data_url, ",") {
    Ok(#(header, base64)) -> {
      let content_type =
        header
        |> string.drop_start(5)
        |> string.split_once(";")
        |> result.map(fn(pair) { pair.0 })
        |> result.unwrap("application/octet-stream")
      #(content_type, base64)
    }
    Error(_) -> #("application/octet-stream", data_url)
  }
}

fn on_file_input(msg: fn(dynamic.Dynamic) -> Msg) -> Attribute(Msg) {
  let raw_decoder = decode.new_primitive_decoder("Dynamic", fn(dyn) { Ok(dyn) })
  event.on("change", {
    use evt <- decode.then(raw_decoder)
    decode.success(msg(evt))
  })
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
            to: RouteNoId(Settings),
            label: "Settings",
          ),
        ]),
      ],
    ),
    case model.route {
      RouteNoId(route) ->
        h.main([a.class("my-16 flex-1")], case route {
          Index -> view_index()
          Posts -> view_posts(model)
          Settings -> view_settings(model)
          NotFound(not_found) -> view_not_found(not_found)
        })
      RoutePatient(id:, patient:, page:) ->
        h.main([a.class("flex flex-1")], [
          h.nav(
            [
              a.class(
                "w-56 shrink-0 bg-slate-800 border-r border-slate-700 flex flex-col items-center p-2",
              ),
            ],
            case patient {
              PatientLoadStillLoading -> {
                [h.text("loading")]
              }
              PatientLoadNotFound(err) -> {
                [h.text("patient " <> id <> " not found: " <> err)]
              }
              PatientLoadFound(data:) -> {
                let photo =
                  data.patient.photo
                  |> list.find_map(utils.get_img_src)
                  |> result.unwrap(patient_photo_placeholder)
                  |> view_patient_photo_box(None)
                // view_patient_photo_box takes Msg to run on click
                // but here we navigate with href/modem instead, and pass None in for msg
                [
                  h.a(
                    [
                      href(RoutePatient(id:, patient:, page: PatientPhotos)),
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
              PatientLoadNotFound(_) -> {
                h.text("loading")
              }
              PatientLoadFound(data:) -> {
                h.div([], case page {
                  PatientOverview -> view_patient_overview(data)
                  PatientAllergies -> view_patient_allergies(data)
                  PatientMedications -> view_patient_medications(data)
                  PatientVitals -> view_patient_vitals(data)
                  PatientPhotos -> view_patient_photos(model, data)
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

fn view_settings(model: Model) -> List(Element(Msg)) {
  let current_url = uri.to_string(model.client.baseurl)
  echo current_url
  let servers = [
    "https://r4.smarthealthit.org/",
    "https://hapi.fhir.org/baseR4",
    "https://server.fire.ly",
  ]
  [
    title("Settings"),
    h.div([a.class("mt-8")], [
      h.p([a.class("mb-4 text-lg")], [h.text("FHIR Server Base URL")]),
      h.div(
        [],
        list.map(servers, fn(url) {
          h.label(
            [
              a.class("my-2 block"),
              event.on_click(UserClickedChangeClient(url)),
            ],
            [
              h.input([
                a.type_("radio"),
                a.name("fhir-server"),
                a.checked(url == current_url),
              ]),
              h.span([a.class("ml-2")], [h.text(url)]),
            ],
          )
        }),
      ),
    ]),
  ]
}

fn view_patient_not_found() {
  svg.svg(
    [
      a.attribute("width", "150px"),
      a.attribute("height", "150px"),
      a.attribute("viewBox", "0 0 150 150"),
      a.attribute("alt", "Patient Photo"),
      a.class("mx-auto block rounded"),
    ],
    [
      svg.path([
        a.attribute("fill", "#ccc"),
        a.attribute(
          "d",
          "M 104.68731,56.689353 C 102.19435,80.640493 93.104981,97.26875 74.372196,97.26875 55.639402,97.26875 46.988823,82.308034 44.057005,57.289941 41.623314,34.938838 55.639402,15.800152 74.372196,15.800152 c 18.732785,0 32.451944,18.493971 30.315114,40.889201 z",
        ),
      ]),
      svg.path([
        a.attribute("fill", "#ccc"),
        a.attribute(
          "d",
          "M 92.5675 89.6048 C 90.79484 93.47893 89.39893 102.4504 94.86478 106.9039 C 103.9375 114.2963 106.7064 116.4723 118.3117 118.9462 C 144.0432 124.4314 141.6492 138.1543 146.5244 149.2206 L 4.268444 149.1023 C 8.472223 138.6518 6.505799 124.7812 32.40051 118.387 C 41.80992 116.0635 45.66513 113.8823 53.58659 107.0158 C 58.52744 102.7329 57.52583 93.99267 56.43084 89.26926 C 52.49275 88.83011 94.1739 88.14054 92.5675 89.6048 z",
        ),
      ]),
    ],
  )
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
          h.text(utils.annotation_first_text(allergy.note)),
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
    h.h1([a.class("text-xl font-bold p-4")], [
      h.text("Allergies and Intolerances"),
    ]),
    h.table([a.class("border-separate border-spacing-4 m-4")], [
      h.thead([], [head]),
      h.tbody([], rows),
    ]),
    h.div([a.class("flex flex-row gap-2")], [
      h.p([], [h.text("inputs")]),
      h.label([a.for("new-allergy-note")], [h.text("note:")]),
      h.input([
        a.class("border border-slate-700 bg-slate-950"),
        a.id("new-allergy-note"),
        event.on_input(fn(input) {
          UserTypedAllergyintoleranceNote(on_id: None, input:)
        }),
        a.value(case pat.patient_allergy_new.note {
          [] -> ""
          [first, ..] -> first.text
        }),
      ]),
      h.input([a.class("border border-slate-700 bg-slate-950")]),
      h.input([a.class("border border-slate-700 bg-slate-950")]),
      h.select(
        [
          a.class("border border-slate-700 bg-slate-950"),
          a.id("choice"),
          a.name("choice"),
        ],
        [
          r4us_valuesets.AllergyintolerancecriticalityLow,
          r4us_valuesets.AllergyintolerancecriticalityHigh,
          r4us_valuesets.AllergyintolerancecriticalityUnabletoassess,
        ]
          |> list.map(fn(criticality) {
            let crit_str =
              r4us_valuesets.allergyintolerancecriticality_to_string(
                criticality,
              )
            h.option(
              [
                a.value(crit_str),
              ],
              crit_str,
            )
          }),
      ),
      h.input([a.class("border border-slate-700 bg-slate-950")]),
      h.button([event.on_click(UserClickedCreateAllergy)], [
        h.text("Save New Allergy/Intolerance"),
      ]),
    ]),
  ]
}

fn view_patient_medications(_model) {
  [h.p([], [h.text("meds")])]
}

fn view_patient_vitals(_model) {
  [h.p([], [h.text("vitals")])]
}

fn view_patient_photos(model: Model, data: PatientData) {
  let photos =
    list.index_map(data.patient.photo, fn(photo, num) {
      case utils.get_img_src(photo) {
        Ok(src) ->
          view_patient_photo_box(
            src,
            Some(event.on_click(UserClickedExistingPhoto(num))),
          )
        Error(_) -> h.div([a.class("hidden")], [])
      }
    })
  let dropzone_class = case model.dragging_photo {
    True ->
      "border-2 border-dashed border-blue-500 bg-blue-50 rounded-lg p-6 text-center transition-colors"
    False ->
      "border-2 border-dashed border-gray-300 rounded-lg p-6 text-center transition-colors"
  }
  [
    h.div([a.class("min-h-full")], [
      h.div([a.class("p-4")], [
        h.div([a.class(dropzone_class)], [
          h.h3([a.class("text-lg mb-2")], [h.text("Upload Photo")]),
          h.label(
            [
              a.class(
                "inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white font-medium rounded cursor-pointer hover:bg-blue-700 active:bg-blue-800 transition-colors",
              ),
            ],
            [
              h.text("Choose File"),
              h.input([
                a.type_("file"),
                a.attribute("accept", "image/*"),
                a.class("hidden"),
                on_file_input(UserSelectedPhotoEvent),
              ]),
            ],
          ),
          h.p([a.class("mt-2 text-sm text-gray-500")], [
            h.text("or drag and drop an image anywhere on this page"),
          ]),
        ]),
      ]),
      h.div([a.class("p-4 flex flex-wrap gap-2")], photos),
    ]),
  ]
}

// VIEW HELPERS ----------------------------------------------------------------

fn view_patient_photo_box(src, click_effect) {
  let attrs = [
    a.src(src),
    a.alt("Patient Photo"),
    a.class(
      "w-48 h-48 object-cover rounded-full hover:opacity-50 transition-opacity cursor-pointer",
    ),
    a.attribute("draggable", "false"),
  ]
  let attrs = case click_effect {
    Some(click_effect) -> [click_effect, ..attrs]
    None -> attrs
  }
  h.img(attrs)
}

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
