import components.{
  CodingOption, btn, btn_cancel, btn_nomsg, view_form_coding_select,
  view_form_input, view_form_select, view_form_textarea,
}
import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import terminology/actcode
import utils

pub fn update(msg, model) {
  case msg {
    mm.ServerCreatedEncounter(Ok(enc), note) -> server_created(model, enc, note)
    mm.ServerCreatedEncounter(Error(_), _) -> #(model, effect.none())
    mm.ServerUpdatedEncounter(Ok(enc), note) -> server_updated(model, enc, note)
    mm.ServerUpdatedEncounter(Error(_), _) -> #(model, effect.none())
    mm.ServerSavedEncounterNote(Ok(doc)) -> server_saved_note(model, doc)
    mm.ServerSavedEncounterNote(Error(_)) -> #(model, effect.none())
    mm.ServerDeletedEncounterNote(_) -> #(model, effect.none())
    mm.ServerDeletedEncounter(_) -> #(model, effect.none())
    mm.UserClickedCreateEncounter -> edit(model, None)
    mm.UserClickedEditEncounter(id) -> edit(model, Some(id))
    mm.UserClickedDeleteEncounter(id) -> delete(model, id)
    mm.UserClickedCloseEncounterForm -> close_form(model)
    mm.UserSubmittedEncounterForm(Ok(new_enc)) -> submit(model, new_enc)
    mm.UserSubmittedEncounterForm(Error(err)) -> form_errors(model, err)
  }
}

pub fn server_created(
  model: Model,
  enc: r4us.Encounter,
  note: Option(r4us.Documentreference),
) -> #(Model, Effect(mm.SubmsgEncounter)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let note_effect = case patient {
        mm.PatientLoadFound(data) ->
          save_note_effect(model.client, data.patient, enc, note)
        _ -> effect.none()
      }
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_encounters = list.append(data.patient_encounters, [enc])
          mm.PatientLoadFound(mm.PatientData(..data, patient_encounters:))
        }
        _ -> patient
      }
      let model =
        model
        |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone)
      #(model, note_effect)
    }
  }
}

pub fn server_updated(
  model: Model,
  updated: r4us.Encounter,
  note: Option(r4us.Documentreference),
) -> #(Model, Effect(mm.SubmsgEncounter)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let note_effect = case patient {
        mm.PatientLoadFound(data) ->
          save_note_effect(model.client, data.patient, updated, note)
        _ -> effect.none()
      }
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_encounters =
            data.patient_encounters
            |> list.map(fn(old) {
              case old.id == updated.id {
                True -> updated
                False -> old
              }
            })
          let patient_documentreferences = case updated.id, note {
            Some(enc_id), Some(doc) ->
              case note_text(Some(doc)) {
                "" ->
                  data.patient_documentreferences
                  |> list.filter(fn(doc) { !references_encounter(doc, enc_id) })
                _ -> data.patient_documentreferences
              }
            _, _ -> data.patient_documentreferences
          }
          mm.PatientLoadFound(mm.PatientData(
            ..data,
            patient_documentreferences:,
            patient_encounters:,
          ))
        }
        _ -> patient
      }
      let model =
        model
        |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone)
      #(model, note_effect)
    }
  }
}

pub fn server_saved_note(
  model: Model,
  saved: r4us.Documentreference,
) -> #(Model, Effect(mm.SubmsgEncounter)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_documentreferences =
            upsert_documentreference(data.patient_documentreferences, saved)
          mm.PatientLoadFound(mm.PatientData(..data, patient_documentreferences:))
        }
        _ -> patient
      }
      #(
        model |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone),
        effect.none(),
      )
    }
  }
}

pub fn edit(model: Model, edit_id: Option(String)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id: pat_id, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) ->
          case edit_id {
            Some(edit_id) ->
              case
                data.patient_encounters
                |> list.find(fn(enc) { enc.id == Some(edit_id) })
              {
                Error(_) -> #(model, effect.none())
                Ok(enc) -> {
                  let note = encounter_note(data.patient_documentreferences, enc)
                  encounter_schema(mm.EncounterNote(encounter: enc, note:))
                  |> form.new
                  |> form.add_string("class", option.unwrap(enc.class.code, ""))
                  |> form.add_string(
                    "status",
                    r4us_valuesets.encounterstatus_to_string(enc.status),
                  )
                  |> form.add_string("period_start", case enc.period {
                    Some(p) ->
                      case p.start {
                        Some(primitive_types.DateTime(date:, ..)) ->
                          date |> primitive_types.date_to_string
                        None -> ""
                      }
                    None -> ""
                  })
                  |> form.add_string("period_end", case enc.period {
                    Some(p) ->
                      case p.end {
                        Some(primitive_types.DateTime(date:, ..)) ->
                          date |> primitive_types.date_to_string
                        None -> ""
                      }
                    None -> ""
                  })
                  |> form.add_string("note", note_text(note))
                  |> form.add_string("id", edit_id)
                  |> form_to_model(model, pat_id, patient)
                }
              }
            None -> {
              let blank =
                r4us.encounter_new(
                  class: r4us.coding_new(),
                  status: r4us_valuesets.EncounterstatusPlanned,
                )
              encounter_schema(mm.EncounterNote(encounter: blank, note: None))
              |> form.new
              |> form_to_model(model, pat_id, patient)
            }
          }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_to_model(encounter_form, model, pat_id, patient) {
  let encounter_form =
    encounter_form
    |> mm.FormStateSome
    |> mm.PatientEncounters
  let route = mm.RoutePatient(id: pat_id, patient:, page: encounter_form)
  let model = Model(..model, route:)
  #(model, effect.none())
}

pub fn submit(model: Model, form_encounter_note: mm.EncounterNote) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let mm.EncounterNote(encounter: form_enc, note:) = form_encounter_note
          let enc_with_subject =
            r4us.Encounter(
              ..form_enc,
              subject: Some(data.patient |> utils.patient_to_reference),
            )
          let effect = case enc_with_subject.id {
            None ->
              r4us_rsvp.encounter_create(
                enc_with_subject,
                model.client,
                fn(result) { mm.ServerCreatedEncounter(result, note) },
              )
            Some(_) ->
              r4us_rsvp.encounter_update(
                enc_with_subject,
                model.client,
                fn(result) { mm.ServerUpdatedEncounter(result, note) },
              )
              |> result.unwrap(effect.none())
          }
          let model =
            model
            |> set_form_state(id:, patient:, formstate: mm.FormStateLoading)
          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn set_form_state(model model, id id, patient patient, formstate formstate) {
  let encounter_form = mm.PatientEncounters(formstate)
  let route = mm.RoutePatient(id:, patient:, page: encounter_form)
  let model = Model(..model, route:)
}

pub fn delete(model: Model, enc_id: String) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) ->
          case
            data.patient_encounters
            |> list.find(fn(e) { e.id == Some(enc_id) })
          {
            Error(_) -> #(model, effect.none())
            Ok(enc) -> {
              let eff =
                [
                  r4us_rsvp.encounter_delete(
                  enc,
                  model.client,
                  mm.ServerDeletedEncounter,
                  )
                  |> result.unwrap(effect.none()),
                  case encounter_note(data.patient_documentreferences, enc) {
                    Some(doc) ->
                      r4us_rsvp.documentreference_delete(
                        doc,
                        model.client,
                        mm.ServerDeletedEncounterNote,
                      )
                      |> result.unwrap(effect.none())
                    None -> effect.none()
                  },
                ]
                |> effect.batch
              let patient_encounters =
                data.patient_encounters
                |> list.filter(fn(e) { e.id != Some(enc_id) })
              let patient_documentreferences =
                data.patient_documentreferences
                |> list.filter(fn(doc) { !references_encounter(doc, enc_id) })
              let new_pat =
                mm.PatientLoadFound(
                  mm.PatientData(
                    ..data,
                    patient_documentreferences:,
                    patient_encounters:,
                  ),
                )
              #(
                model
                  |> set_form_state(
                    id:,
                    patient: new_pat,
                    formstate: mm.FormStateNone,
                  ),
                eff,
              )
            }
          }
        _ -> #(model, effect.none())
      }
  }
}

pub fn close_form(model: Model) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) -> #(
      model |> set_form_state(id:, patient:, formstate: mm.FormStateNone),
      effect.none(),
    )
  }
}

pub fn form_errors(model: Model, err: Form(mm.EncounterNote)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientEncounters(mm.FormStateSome(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

pub fn encounter_schema(encounter_note: mm.EncounterNote) {
  let mm.EncounterNote(encounter: enc, note: existing_note) = encounter_note
  use class <- form.field(
    "class",
    form.parse(fn(input) {
      let str = case input {
        [s, ..] -> s
        [] -> ""
      }
      case list.find(actcode.v3_actencountercode, fn(e) { e.0 == str }) {
        Ok(#(code_val, display)) ->
          Ok(utils.coding(code: code_val, system: actcode.system, display:))
        Error(_) -> Error(#(enc.class, "Must choose a class"))
      }
    }),
  )
  use status <- form.field(
    "status",
    form.parse(fn(input) {
      let str = case input {
        [s, ..] -> s
        [] -> ""
      }
      case r4us_valuesets.encounterstatus_from_string(str) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(#(enc.status, "Must choose a status"))
      }
    }),
  )
  use period_start_str <- form.field(
    "period_start",
    form.parse_optional(form.parse_string),
  )
  use period_end_str <- form.field(
    "period_end",
    form.parse_optional(form.parse_string),
  )
  use note_text <- form.field("note", form.parse_string)
  let start = case period_start_str {
    Some(s) ->
      case primitive_types.parse_datetime(s) {
        Ok(d) -> Some(d)
        Error(_) -> None
      }
    None -> None
  }
  let end = case period_end_str {
    Some(s) ->
      case primitive_types.parse_datetime(s) {
        Ok(d) -> Some(d)
        Error(_) -> None
      }
    None -> None
  }
  let period = case start, end {
    None, None -> None
    _, _ -> Some(r4us.Period(..r4us.period_new(), start:, end:))
  }
  form.success(
    mm.EncounterNote(
      encounter: r4us.Encounter(..enc, class:, status:, period:),
      note: note_from_text(existing_note, note_text),
    ),
  )
}

fn encounter_reference(enc_id: String) {
  "Encounter/" <> enc_id
}

fn reference_to_encounter(enc_id: String) {
  r4us.Reference(
    ..r4us.reference_new(),
    reference: Some(encounter_reference(enc_id)),
  )
}

fn references_encounter(doc: r4us.Documentreference, enc_id: String) {
  case doc.context {
    Some(context) ->
      context.encounter
      |> list.any(fn(ref) { ref.reference == Some(encounter_reference(enc_id)) })
    None -> False
  }
}

fn encounter_note(
  docs: List(r4us.Documentreference),
  enc: r4us.Encounter,
) -> Option(r4us.Documentreference) {
  case enc.id {
    Some(enc_id) ->
      case docs |> list.find(fn(doc) { references_encounter(doc, enc_id) }) {
        Ok(doc) -> Some(doc)
        Error(_) -> None
      }
    None -> None
  }
}

fn note_from_text(
  existing_note: Option(r4us.Documentreference),
  text: String,
) -> Option(r4us.Documentreference) {
  case existing_note, string.trim(text) {
    None, "" -> None
    Some(doc), "" -> Some(r4us.Documentreference(..doc, content: note_content("")))
    _, text -> {
      let doc = case existing_note {
        Some(doc) -> doc
        None ->
          r4us.documentreference_new(
            content: note_content(text),
            status: r4us_valuesets.DocumentreferencestatusCurrent,
          )
      }
      Some(r4us.Documentreference(
        ..doc,
        content: note_content(text),
        description: Some("Encounter note"),
        status: r4us_valuesets.DocumentreferencestatusCurrent,
      ))
    }
  }
}

fn note_content(text: String) {
  let attachment =
    r4us.Attachment(
      ..r4us.attachment_new(),
      content_type: Some("text/plain"),
      data: Some(text |> bit_array.from_string |> bit_array.base64_encode(True)),
    )
  r4us.List1(r4us.documentreference_content_new(attachment:), [])
}

fn note_text(note: Option(r4us.Documentreference)) -> String {
  case note {
    Some(doc) -> {
      let r4us.List1(first: first_content, rest: _) = doc.content
      case first_content.attachment.data {
        Some(data) ->
          data
          |> bit_array.base64_decode
          |> result.try(bit_array.to_string)
          |> result.unwrap("")
        None -> ""
      }
    }
    None -> ""
  }
}

fn save_note_effect(
  client: r4us_rsvp.FhirClient,
  patient: r4us.Patient,
  enc: r4us.Encounter,
  note: Option(r4us.Documentreference),
) -> Effect(mm.SubmsgEncounter) {
  case enc.id, note {
    Some(enc_id), Some(doc) -> {
      case note_text(Some(doc)) {
        "" ->
          r4us_rsvp.documentreference_delete(
            doc,
            client,
            mm.ServerDeletedEncounterNote,
          )
          |> result.unwrap(effect.none())
        _ -> {
          let doc =
            r4us.Documentreference(
              ..doc,
              subject: Some(patient |> utils.patient_to_reference),
              context: Some(r4us.DocumentreferenceContext(
                ..r4us.documentreference_context_new(),
                encounter: [reference_to_encounter(enc_id)],
              )),
            )
          case doc.id {
            Some(_) ->
              r4us_rsvp.documentreference_update(
                doc,
                client,
                mm.ServerSavedEncounterNote,
              )
              |> result.unwrap(effect.none())
            None ->
              r4us_rsvp.documentreference_create(
                doc,
                client,
                mm.ServerSavedEncounterNote,
              )
          }
        }
      }
    }
    _, _ -> effect.none()
  }
}

fn upsert_documentreference(
  docs: List(r4us.Documentreference),
  saved: r4us.Documentreference,
) {
  case saved.id {
    None -> docs
    Some(saved_id) -> {
      let exists =
        docs
        |> list.any(fn(doc) { doc.id == Some(saved_id) })
      case exists {
        True ->
          docs
          |> list.map(fn(doc) {
            case doc.id == Some(saved_id) {
              True -> saved
              False -> doc
            }
          })
        False -> list.append(docs, [saved])
      }
    }
  }
}

fn class_display(code: String) -> String {
  actcode.v3_actencountercode
  |> list.find(fn(entry) { entry.0 == code })
  |> result.map(fn(entry) { entry.1 })
  |> result.unwrap(code)
}

pub fn view(
  pat: mm.PatientData,
  encounter_form: mm.FormState(mm.EncounterNote),
) {
  let head =
    h.tr(
      [],
      utils.th_list(["class", "status", "start", "end", "note", ""]),
    )
  let rows =
    list.map(pat.patient_encounters, fn(enc) {
      case enc.id {
        None -> element.none()
        Some(enc_id) ->
          h.tr([a.class("border-b border-slate-700")], [
            h.td([a.class("p-2")], [
              h.text(class_display(option.unwrap(enc.class.code, ""))),
            ]),
            h.td([a.class("p-2")], [
              h.text(r4us_valuesets.encounterstatus_to_string(enc.status)),
            ]),
            h.td([a.class("p-2")], [
              case enc.period {
                Some(p) ->
                  case p.start {
                    Some(d) -> h.text(d |> primitive_types.datetime_to_string)
                    None -> element.none()
                  }
                None -> element.none()
              },
            ]),
            h.td([a.class("p-2")], [
              case enc.period {
                Some(p) ->
                  case p.end {
                    Some(d) -> h.text(d |> primitive_types.datetime_to_string)
                    None -> element.none()
                  }
                None -> element.none()
              },
            ]),
            h.td([a.class("p-2 max-w-xs truncate")], [
              h.text(note_text(encounter_note(pat.patient_documentreferences, enc))),
            ]),
            h.td([a.class("p-2 flex gap-2")], [
              btn("Edit", on_click: mm.UserClickedEditEncounter(enc_id)),
              btn("Delete", on_click: mm.UserClickedDeleteEncounter(enc_id)),
            ]),
          ])
      }
    })
  [
    h.div([a.class("p-4 max-w-4xl")], [
      h.div([a.class("flex items-center gap-4 mb-4")], [
        h.h1([a.class("text-xl font-bold")], [h.text("Encounters")]),
        btn("Create New Encounter", on_click: mm.UserClickedCreateEncounter),
      ]),
      h.table([a.class("border-collapse border border-slate-700")], [
        h.thead([], [head]),
        h.tbody([], rows),
      ]),
      case encounter_form {
        mm.FormStateNone -> element.none()
        mm.FormStateLoading -> h.p([], [h.text("loading...")])
        mm.FormStateSome(encounter_form) -> {
          let legend_text = case form.field_value(encounter_form, "id") {
            "" -> "Create Encounter"
            _ -> {
              let code = form.field_value(encounter_form, "class")
              "Edit " <> class_display(code)
            }
          }
          h.form(
            [
              a.class("max-w-2xl"),
              event.on_submit(fn(values) {
                encounter_form
                |> form.add_values(values)
                |> form.run
                |> mm.UserSubmittedEncounterForm
              }),
            ],
            [
              h.fieldset(
                [
                  a.class(
                    "border border-slate-700 rounded-lg p-4 flex flex-row flex-wrap gap-4",
                  ),
                ],
                [
                  h.legend([a.class("px-2 text-sm font-bold text-slate-200")], [
                    h.text(legend_text),
                  ]),
                  view_form_coding_select(
                    encounter_form,
                    name: "class",
                    options: list.map(actcode.v3_actencountercode, fn(entry) {
                      CodingOption(
                        code: entry.0,
                        display: entry.1,
                        system: actcode.system,
                      )
                    }),
                    label: "class",
                  ),
                  view_form_select(
                    encounter_form,
                    name: "status",
                    options: [
                      r4us_valuesets.EncounterstatusPlanned,
                      r4us_valuesets.EncounterstatusArrived,
                      r4us_valuesets.EncounterstatusTriaged,
                      r4us_valuesets.EncounterstatusInprogress,
                      r4us_valuesets.EncounterstatusOnleave,
                      r4us_valuesets.EncounterstatusFinished,
                      r4us_valuesets.EncounterstatusCancelled,
                    ]
                      |> list.map(r4us_valuesets.encounterstatus_to_string),
                    label: "status",
                  ),
                  view_form_input(
                    encounter_form,
                    is: "date",
                    name: "period_start",
                    label: "start",
                  ),
                  view_form_input(
                    encounter_form,
                    is: "date",
                    name: "period_end",
                    label: "end",
                  ),
                  view_form_textarea(
                    encounter_form,
                    name: "note",
                    label: "note",
                  ),
                  h.div([a.class("w-full flex justify-end gap-2")], [
                    btn_cancel(
                      "Cancel",
                      on_click: mm.UserClickedCloseEncounterForm,
                    ),
                    btn_nomsg("Save Encounter"),
                  ]),
                ],
              ),
            ],
          )
        }
      },
    ]),
  ]
}
