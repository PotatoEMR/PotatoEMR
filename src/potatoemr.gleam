import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
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
import pages/no_id/index
import pages/no_id/notfound
import pages/no_id/registerpatient
import pages/no_id/settings
import pages/patient/allergy
import pages/patient/demographics
import pages/patient/encounters
import pages/patient/immunization
import pages/patient/medications
import pages/patient/orders
import pages/patient/overview
import pages/patient/photo
import pages/patient/vitals
import utils
import utils2
import colors

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
        fn(dragging) { dispatch(mm.MsgPhoto(mm.UserDraggingPhoto(dragging))) },
        fn(data_url) {
          dispatch(mm.MsgPhoto(mm.UserSelectedPhotoDataUrl(data_url)))
        },
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
                <> "&_revinclude=AllergyIntolerance:patient&_revinclude=DocumentReference:patient&_revinclude=Immunization:patient&_revinclude=MedicationRequest:patient&_revinclude=MedicationStatement:patient&_revinclude=Observation:patient&_revinclude=Condition:patient&_revinclude=Encounter:patient",
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
    mm.ServerReturnedSearchPatients(Error(err)) -> {
      #(
        model
          |> set_search_result(mm.SearchPatientResultsErrMsg(
            "There was a problem getting patient search from FHIR server: "
            <> utils.err_to_string(err),
          )),
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
            patient_documentreferences: resources.documentreference,
            patient_encounters: resources.encounter,
            patient_immunizations: resources.immunization,
            patient_medications: resources.medication,
            patient_medication_requests: resources.medicationrequest,
            patient_medication_statements: resources.medicationstatement,
            patient_observations: resources.observation,
          ))
      }
      utils2.update_patient(model, fn(_oldpat) { pat })
    }
    mm.ServerReturnedPatientEverything(Error(err)) ->
      utils2.update_patient(model, fn(_oldpat) {
        echo err
        mm.PatientLoadNotFound(utils.err_to_string(err))
      })
    mm.MsgDemographics(msg) ->
      sub_update(msg, model, demographics.update, mm.MsgDemographics)
    mm.MsgSettings(msg) ->
      sub_update(msg, model, settings.update, mm.MsgSettings)
    mm.MsgPhoto(msg) -> sub_update(msg, model, photo.update, mm.MsgPhoto)
    mm.MsgAllergy(msg) -> sub_update(msg, model, allergy.update, mm.MsgAllergy)
    mm.MsgEncounter(msg) ->
      sub_update(msg, model, encounters.update, mm.MsgEncounter)
    mm.MsgImmunization(msg) ->
      sub_update(msg, model, immunization.update, mm.MsgImmunization)
    mm.MsgMedication(msg) ->
      sub_update(msg, model, medications.update, mm.MsgMedication)
    mm.MsgOrder(msg) -> sub_update(msg, model, orders.update, mm.MsgOrder)
    mm.MsgVitals(msg) -> sub_update(msg, model, vitals.update, mm.MsgVitals)
    mm.MsgRegisterPatient(msg) ->
      sub_update(msg, model, registerpatient.update, mm.MsgRegisterPatient)
  }
}

pub fn sub_update(model, msg, sub_update_fn, sub_update_type) {
  let #(model, eff) = sub_update_fn(model, msg)
  #(model, effect.map(eff, sub_update_type))
}

fn set_search_result(model: Model, results: mm.SearchPatientResults) {
  Model(..model, search: mm.SearchPatient(..model.search, results:))
}

fn set_search_visible(model: Model, visible: Bool) {
  Model(..model, search: mm.SearchPatient(..model.search, visible:))
}

// VIEW ------------------------------------------------------------------------

const nav_bar_class = "flex flex-wrap items-end space-x-1 px-2 min-h-10 " <> colors.bg_slate_800 <> " border-b " <> colors.border_slate_700

fn view(model: Model) -> Element(Msg) {
  h.div([a.class("w-full h-dvh flex flex-col " <> colors.bg_slate_900 <> " " <> colors.text_white)], [
    h.nav([a.class(nav_bar_class)], [
      h.div([a.class("relative")], [
        h.input([
          a.class(
            "w-lg max-w-[calc(100vw-2rem)] h-8 m-1 pl-4 rounded-full border " <> colors.border_slate_700 <> " " <> colors.bg_slate_950 <> " focus:outline " <> colors.focus_outline_purple_600,
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
                  "absolute top-full left-0 -mt-1 " <> colors.bg_slate_800 <> " border " <> colors.border_slate_700 <> " w-3xl max-w-[calc(100vw-1rem)] h-120 max-h-[calc(100dvh-4rem)] overflow-auto z-50",
                ),
                event.prevent_default(event.on_mouse_down(mm.UserFocusedSearch)),
              ],
              case model.search.results {
                mm.SearchPatientResultsErrMsg(err_msg:) -> [
                  h.p([a.class(colors.text_red_300)], [h.text(err_msg)]),
                ]
                mm.SearchPatientResultsLoadingMsg -> [h.text("loading...")]
                mm.SearchPatientResultsEmptyMsg -> [h.text("type name to search patient by name")]
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
                              Some(bd) -> bd |> primitive_types.date_to_string
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
                                  "flex items-center gap-3 p-4 " <> colors.hover_bg_slate_900,
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
                                  h.p([a.class("text-sm " <> colors.text_slate_400)], [
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
      ..{
        mm.pages_no_id
        |> list.map(fn(link) {
          view_header_link(
            current: model.route,
            to: mm.RouteNoId(link.1),
            label: link.0,
          )
        })
      }
    ]),
    {
      case model.route {
        mm.RouteNoId(route) ->
          h.main([a.class("flex-1 min-h-0 overflow-y-auto")], case route {
            mm.Index -> index.view()
            mm.Settings -> settings.view(model) |> sub_view(mm.MsgSettings)
            mm.RegisterPatient(newpatient) ->
              registerpatient.view(newpatient)
              |> sub_view(mm.MsgRegisterPatient)
            mm.NotFound(not_found) -> notfound.view(not_found)
          })
        mm.RoutePatient(id:, patient:, page:) ->
          h.main([a.class("flex flex-col md:flex-row flex-1 min-h-0")], [
            h.nav(
              [
                a.class(
                  "w-full md:w-56 shrink-0 " <> colors.bg_slate_800 <> " border-b md:border-b-0 md:border-r " <> colors.border_slate_700 <> " flex flex-row md:flex-col items-center gap-2 md:gap-0 p-2",
                ),
              ],
              case patient {
                mm.PatientLoadStillLoading -> {
                  [h.text("loading")]
                }
                mm.PatientLoadNotFound(err) -> {
                  [h.text("patient " <> id <> " error: " <> err)]
                }
                mm.PatientLoadFound(data:) -> {
                  let photo =
                    data.patient.photo
                    |> list.find_map(utils.get_img_src)
                    |> result.unwrap(patient_photo_placeholder)
                    |> utils.view_patient_photo_box(None)
                  // view_patient_photo_box takes Msg to run on click
                  // but here we navigate with href/modem instead, and pass None in for msg
                  let recorded_gender = case
                    data.patient.individual_recorded_sex_or_gender
                  {
                    [first, ..] -> utils.codeableconcept_to_string(first.value)
                    [] -> ""
                  }
                  let gender = case recorded_gender {
                    "" ->
                      case data.patient.gender {
                        Some(g) ->
                          r4us_valuesets.administrativegender_to_string(g)
                        None -> ""
                      }
                    s -> s
                  }
                  let birth_date = case data.patient.birth_date {
                    Some(bd) -> primitive_types.date_to_string(bd)
                    None -> ""
                  }
                  let pcp = case data.patient.general_practitioner {
                    [] -> ""
                    [first, ..] ->
                      case first.display {
                        Some(s) -> s
                        None -> option.unwrap(first.reference, "")
                      }
                  }
                  let encounter_start_key = fn(enc: r4us.Encounter) {
                    case enc.period {
                      Some(p) ->
                        case p.start {
                          Some(d) -> primitive_types.datetime_to_string(d)
                          None -> ""
                        }
                      None -> ""
                    }
                  }
                  let attending = case
                    data.patient_encounters
                    |> list.sort(fn(a, b) {
                      string.compare(
                        encounter_start_key(b),
                        encounter_start_key(a),
                      )
                    })
                  {
                    [] -> ""
                    [enc, ..] ->
                      list.find_map(enc.participant, fn(p) {
                        case p.individual {
                          Some(ref) ->
                            case option.unwrap(ref.reference, "") {
                              "Practitioner/" <> _ ->
                                Ok(option.unwrap(
                                  ref.display,
                                  option.unwrap(ref.reference, ""),
                                ))
                              _ -> Error(Nil)
                            }
                          None -> Error(Nil)
                        }
                      })
                      |> result.unwrap("")
                  }
                  let #(allergies_label, allergies_list) = case
                    data.patient_allergies
                  {
                    [] -> #("No Known Allergies", element.none())
                    allergies -> #(
                      "Allergies",
                      h.ul(
                        [a.class(colors.text_slate_400 <> " list-disc pl-5")],
                        list.map(allergies, fn(al) {
                          let name = case al.code {
                            None -> "unspecified"
                            Some(cc) -> utils.codeableconcept_to_string(cc)
                          }
                          h.li([], [h.text(name)])
                        }),
                      ),
                    )
                  }
                  let allergies_section =
                    h.div(
                      [a.class("hidden md:flex flex-col w-full mt-3 text-sm")],
                      [
                        h.div([a.class("font-semibold " <> colors.text_slate_300)], [
                          h.text(allergies_label),
                        ]),
                        allergies_list,
                      ],
                    )
                  let #(meds_label, meds_list) = case
                    data.patient_medication_statements
                  {
                    [] -> #("No Known Medications", element.none())
                    meds -> #(
                      "Medications",
                      h.ul(
                        [a.class(colors.text_slate_400 <> " list-disc pl-5")],
                        list.map(meds, fn(ms) {
                          let name = case ms.medication {
                            r4us.MedicationstatementMedicationCodeableconcept(
                              cc,
                            ) -> utils.codeableconcept_to_string(cc)
                            r4us.MedicationstatementMedicationReference(ref) ->
                              option.unwrap(ref.display, "")
                          }
                          h.li([], [h.text(name)])
                        }),
                      ),
                    )
                  }
                  let medications_section =
                    h.div(
                      [a.class("hidden md:flex flex-col w-full mt-3 text-sm")],
                      [
                        h.div([a.class("font-semibold " <> colors.text_slate_300)], [
                          h.text(meds_label),
                        ]),
                        meds_list,
                      ],
                    )
                  [
                    h.a(
                      [
                        href(mm.RoutePatient(
                          id:,
                          patient:,
                          page: mm.PatientPhotos(None),
                        )),
                      ],
                      [photo],
                    ),
                    h.div([a.class("font-semibold text-center")], [
                      h.text(
                        patient.data.patient.name
                        |> utils.humannames_to_single_name_string,
                      ),
                    ]),
                    case gender {
                      "" -> element.none()
                      s ->
                        h.div([a.class("text-sm " <> colors.text_slate_400)], [h.text(s)])
                    },
                    case birth_date {
                      "" -> element.none()
                      s ->
                        h.div([a.class("text-sm " <> colors.text_slate_400)], [h.text(s)])
                    },
                    case pcp {
                      "" -> element.none()
                      s ->
                        h.div([a.class("text-sm " <> colors.text_slate_400)], [
                          h.text("PCP: " <> s),
                        ])
                    },
                    case attending {
                      "" -> element.none()
                      s ->
                        h.div([a.class("text-sm " <> colors.text_slate_400)], [
                          h.text("Attending: " <> s),
                        ])
                    },
                    allergies_section,
                    medications_section,
                  ]
                }
              },
            ),
            h.div([a.class("flex-1 flex flex-col min-h-0 min-w-0")], [
              h.ul(
                [a.class(nav_bar_class <> " overflow-x-auto")],
                mm.pages_patient
                  |> list.filter(fn(x) {
                    case x.1 {
                      mm.PatientPhotos(_) -> False
                      _ -> True
                    }
                  })
                  |> list.map(fn(link) {
                    view_header_link(
                      current: model.route,
                      to: mm.RoutePatient(
                        id,
                        mm.PatientLoadStillLoading,
                        link.1,
                      ),
                      label: link.0,
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
                  h.div([a.class("flex-1 overflow-y-auto")], case page {
                    mm.PatientOverview -> overview.view(data)
                    mm.PatientDemographics(demo_form) ->
                      demographics.view(data, demo_form)
                      |> sub_view(mm.MsgDemographics)
                    mm.PatientAllergies(allergy_form) ->
                      allergy.view(data, allergy_form)
                      |> sub_view(mm.MsgAllergy)
                    mm.PatientEncounters(encounter_form) ->
                      encounters.view(data, encounter_form)
                      |> sub_view(mm.MsgEncounter)
                    mm.PatientImmunizations(immunization_form) ->
                      immunization.view(data, immunization_form)
                      |> sub_view(mm.MsgImmunization)
                    mm.PatientMedications(medication_form) ->
                      medications.view(data, medication_form)
                      |> sub_view(mm.MsgMedication)
                    mm.PatientOrders(order_form) ->
                      orders.view(data, order_form)
                      |> sub_view(mm.MsgOrder)
                    mm.PatientVitals(vitals_form) ->
                      vitals.view(data, vitals_form)
                      |> sub_view(mm.MsgVitals)
                    mm.PatientPhotos(_) ->
                      photo.view(model, data)
                      |> sub_view(mm.MsgPhoto)
                  })
                }
              },
            ]),
          ])
      }
    },
  ])
}

fn sub_view(sub_view_fn, sub_msg) {
  sub_view_fn |> list.map(fn(el) { element.map(el, sub_msg) })
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
          #(
            "flex items-center px-3 py-1 rounded-t-2xl border-x border-t underline",
            True,
          ),
          #(colors.hover_text_slate_300 <> " " <> colors.border_transparent, !active),
          #(colors.bg_0f172b <> " " <> colors.border_slate_700, active),
        ]),
      ],
      [h.text(text)],
    ),
  ])
}
