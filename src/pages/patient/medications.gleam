import components.{
  CodingOption, btn, btn_cancel, btn_nomsg, view_form_coding_select,
  view_form_input, view_form_select, view_form_textarea,
}
import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import terminology/medicationcodes
import utils

pub fn update(msg, model) {
  case msg {
    mm.ServerCreatedMedication(Ok(ms), _) -> server_created(model, ms)
    mm.ServerCreatedMedication(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerUpdatedMedication(Ok(ms), _) -> server_updated(model, ms)
    mm.ServerUpdatedMedication(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerDeletedMedication(Ok(_)) -> #(model, effect.none())
    mm.ServerDeletedMedication(Error(_)) -> #(model, effect.none())
    mm.UserClickedCreateMedication -> edit(model, None)
    mm.UserClickedEditMedication(id) -> edit(model, Some(id))
    mm.UserClickedDeleteMedication(id) -> delete(model, id)
    mm.UserClickedCloseMedicationForm -> close_form(model)
    mm.UserSubmittedMedicationForm(Ok(new_ms)) -> submit(model, new_ms)
    mm.UserSubmittedMedicationForm(Error(err)) -> form_errors(model, err)
  }
}

pub fn server_created(
  model: Model,
  ms: r4us.Medicationstatement,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_medication_statements =
            list.append(data.patient_medication_statements, [ms])
          mm.PatientLoadFound(
            mm.PatientData(..data, patient_medication_statements:),
          )
        }
        _ -> patient
      }
      let model =
        model
        |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone)
      #(model, effect.none())
    }
  }
}

pub fn server_updated(
  model: Model,
  updated: r4us.Medicationstatement,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_medication_statements =
            data.patient_medication_statements
            |> list.map(fn(old) {
              case old.id == updated.id {
                True -> updated
                False -> old
              }
            })
          mm.PatientLoadFound(
            mm.PatientData(..data, patient_medication_statements:),
          )
        }
        _ -> patient
      }
      let model =
        model
        |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone)
      #(model, effect.none())
    }
  }
}

pub fn edit(model: Model, edit_id: Option(String)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id: pat_id, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) ->
          case edit_id {
            Some(edit_id) ->
              case
                data.patient_medication_statements
                |> list.find(fn(ms) { ms.id == Some(edit_id) })
              {
                Error(_) -> #(model, effect.none())
                Ok(ms) ->
                  medstmt_schema(ms)
                  |> form.new
                  |> form.add_string("code", case ms.medication {
                    r4us.MedicationstatementMedicationCodeableconcept(cc) ->
                      case cc.coding {
                        [first, ..] -> option.unwrap(first.code, "")
                        [] -> ""
                      }
                    _ -> ""
                  })
                  |> form.add_string(
                    "status",
                    r4us_valuesets.medicationstatementstatus_to_string(
                      ms.status,
                    ),
                  )
                  |> form.add_string("effective", case ms.effective {
                    Some(r4us.MedicationstatementEffectiveDatetime(dt)) ->
                      dt |> primitive_types.datetime_to_string
                    _ -> ""
                  })
                  |> form.add_string(
                    "note",
                    utils.annotation_first_text(ms.note),
                  )
                  |> form.add_string("id", edit_id)
                  |> form_to_model(model, pat_id, patient)
              }
            None -> {
              let blank =
                r4us.medicationstatement_new(
                  subject: data.patient |> utils.patient_to_reference,
                  medication: r4us.MedicationstatementMedicationCodeableconcept(
                    r4us.codeableconcept_new(),
                  ),
                  status: r4us_valuesets.MedicationstatementstatusActive,
                )
              medstmt_schema(blank)
              |> form.new
              |> form_to_model(model, pat_id, patient)
            }
          }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_to_model(medication_form, model, pat_id, patient) {
  let medication_form =
    medication_form
    |> mm.FormStateSome
    |> mm.PatientMedications
  let route = mm.RoutePatient(id: pat_id, patient:, page: medication_form)
  #(Model(..model, route:), effect.none())
}

pub fn server_error(
  model: Model,
  submitted_form: Form(r4us.Medicationstatement),
  err: r4us_rsvp.Err,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let medication_form =
        submitted_form
        |> form.add_error(
          "code",
          form.CustomError("Server error: " <> utils.err_to_string(err)),
        )
        |> mm.FormStateSome
        |> mm.PatientMedications
      let route = mm.RoutePatient(id:, patient:, page: medication_form)
      #(Model(..model, route:), effect.none())
    }
  }
}

pub fn submit(model: Model, form_ms: r4us.Medicationstatement) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let submitted_form = case page {
            mm.PatientMedications(mm.FormStateSome(f)) -> f
            _ -> form.new(medstmt_schema(form_ms))
          }
          let ms_with_subject =
            r4us.Medicationstatement(
              ..form_ms,
              subject: data.patient |> utils.patient_to_reference,
            )
          let effect = case ms_with_subject.id {
            None ->
              r4us_rsvp.medicationstatement_create(
                ms_with_subject,
                model.client,
                fn(result) {
                  mm.ServerCreatedMedication(result, submitted_form)
                },
              )
            Some(_) ->
              r4us_rsvp.medicationstatement_update(
                ms_with_subject,
                model.client,
                fn(result) {
                  mm.ServerUpdatedMedication(result, submitted_form)
                },
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
  let medication_form = mm.PatientMedications(formstate)
  let route = mm.RoutePatient(id:, patient:, page: medication_form)
  Model(..model, route:)
}

pub fn delete(model: Model, ms_id: String) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) ->
          case
            data.patient_medication_statements
            |> list.find(fn(m) { m.id == Some(ms_id) })
          {
            Error(_) -> #(model, effect.none())
            Ok(ms) -> {
              let eff =
                r4us_rsvp.medicationstatement_delete(
                  ms,
                  model.client,
                  mm.ServerDeletedMedication,
                )
                |> result.unwrap(effect.none())
              let patient_medication_statements =
                data.patient_medication_statements
                |> list.filter(fn(m) { m.id != Some(ms_id) })
              let new_pat =
                mm.PatientLoadFound(
                  mm.PatientData(..data, patient_medication_statements:),
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
    mm.RoutePatient(id:, patient:, page: _) -> #(
      model |> set_form_state(id:, patient:, formstate: mm.FormStateNone),
      effect.none(),
    )
  }
}

pub fn form_errors(model: Model, err: Form(r4us.Medicationstatement)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientMedications(mm.FormStateSome(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

pub fn medstmt_schema(ms: r4us.Medicationstatement) {
  use medication <- form.field(
    "code",
    form.parse(fn(input) {
      let str = case input {
        [s, ..] -> s
        [] -> ""
      }
      case list.find(medicationcodes.medication_codes, fn(e) { e.0 == str }) {
        Ok(#(code_val, display)) ->
          Ok(r4us.MedicationstatementMedicationCodeableconcept(
            r4us.Codeableconcept(
              ..r4us.codeableconcept_new(),
              text: Some(display),
              coding: [
                utils.coding(
                  code: code_val,
                  system: "http://snomed.info/sct",
                  display:,
                ),
              ],
            ),
          ))
        Error(_) -> Error(#(ms.medication, "Must choose a medication"))
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
      case r4us_valuesets.medicationstatementstatus_from_string(str) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(#(ms.status, "Must choose a status"))
      }
    }),
  )
  use form_effective <- form.field(
    "effective",
    form.parse_optional(form.parse_string),
  )
  let effective = case form_effective {
    Some(d) ->
      case primitive_types.parse_datetime(d) {
        Ok(d) -> Some(r4us.MedicationstatementEffectiveDatetime(d))
        Error(_) -> None
      }
    None -> None
  }
  use note_text <- form.field("note", form.parse_string)
  let note = case note_text {
    "" -> []
    _ -> [r4us.annotation_new(note_text)]
  }
  form.success(
    r4us.Medicationstatement(..ms, medication:, status:, effective:, note:),
  )
}

pub fn view(
  pat: mm.PatientData,
  medication_form: mm.FormState(r4us.Medicationstatement),
) {
  let head =
    h.tr([], utils.th_list(["medication", "status", "effective", "notes", ""]))
  let rows =
    list.map(pat.patient_medication_statements, fn(ms) {
      case ms.id {
        None -> element.none()
        Some(ms_id) ->
          h.tr([a.class("border-b border-slate-700")], [
            h.td([a.class("p-2")], [
              case ms.medication {
                r4us.MedicationstatementMedicationCodeableconcept(cc) ->
                  h.p([], [h.text(utils.codeableconcept_to_string(cc))])
                r4us.MedicationstatementMedicationReference(ref) ->
                  h.p([], [h.text(option.unwrap(ref.display, ""))])
              },
            ]),
            h.td([a.class("p-2")], [
              h.text(r4us_valuesets.medicationstatementstatus_to_string(
                ms.status,
              )),
            ]),
            h.td([a.class("p-2")], [
              case ms.effective {
                Some(r4us.MedicationstatementEffectiveDatetime(dt)) ->
                  h.text(dt |> primitive_types.datetime_to_string)
                _ -> element.none()
              },
            ]),
            h.td([a.class("p-2 max-w-xs truncate")], [
              h.text(utils.annotation_first_text(ms.note)),
            ]),
            h.td([a.class("p-2 flex gap-2")], [
              btn("Edit", on_click: mm.UserClickedEditMedication(ms_id)),
              btn("Delete", on_click: mm.UserClickedDeleteMedication(ms_id)),
            ]),
          ])
      }
    })
  [
    h.div([a.class("p-4 max-w-4xl")], [
      h.div([a.class("flex items-center gap-4 mb-4")], [
        h.h1([a.class("text-xl font-bold")], [h.text("Medications")]),
        btn("Create New Medication", on_click: mm.UserClickedCreateMedication),
      ]),
      h.table([a.class("border-collapse border border-slate-700")], [
        h.thead([], [head]),
        h.tbody([], rows),
      ]),
      case medication_form {
        mm.FormStateNone -> element.none()
        mm.FormStateLoading -> h.p([], [h.text("loading...")])
        mm.FormStateSome(medication_form) -> {
          let legend_text = case form.field_value(medication_form, "id") {
            "" -> "Create Medication"
            _ -> {
              let code = form.field_value(medication_form, "code")
              let display =
                medicationcodes.medication_codes
                |> list.find(fn(entry) { entry.0 == code })
                |> result.map(fn(entry) { entry.1 })
                |> result.unwrap(code)
              "Edit " <> display
            }
          }
          h.form(
            [
              a.class("max-w-2xl"),
              event.on_submit(fn(values) {
                medication_form
                |> form.add_values(values)
                |> form.run
                |> mm.UserSubmittedMedicationForm
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
                    medication_form,
                    name: "code",
                    options: list.map(
                      medicationcodes.medication_codes,
                      fn(entry) {
                        CodingOption(
                          code: entry.0,
                          display: entry.1,
                          system: "http://snomed.info/sct",
                        )
                      },
                    ),
                    label: "medication",
                  ),
                  view_form_select(
                    medication_form,
                    name: "status",
                    options: [
                      r4us_valuesets.MedicationstatementstatusActive,
                      r4us_valuesets.MedicationstatementstatusCompleted,
                      r4us_valuesets.MedicationstatementstatusIntended,
                      r4us_valuesets.MedicationstatementstatusStopped,
                      r4us_valuesets.MedicationstatementstatusOnhold,
                      r4us_valuesets.MedicationstatementstatusNottaken,
                    ]
                      |> list.map(
                        r4us_valuesets.medicationstatementstatus_to_string,
                      ),
                    label: "status",
                  ),
                  view_form_input(
                    medication_form,
                    is: "date",
                    name: "effective",
                    label: "effective",
                  ),
                  view_form_textarea(
                    medication_form,
                    name: "note",
                    label: "note",
                  ),
                  h.div([a.class("w-full flex justify-end gap-2")], [
                    btn_cancel(
                      "Cancel",
                      on_click: mm.UserClickedCloseMedicationForm,
                    ),
                    btn_nomsg("Save Medication"),
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
