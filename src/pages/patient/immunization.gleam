import components.{
  CodingOption, btn, btn_cancel, btn_nomsg, view_form_coding_select,
  view_form_input, view_form_select, view_form_textarea,
}
import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import terminology/vaccinecodes
import utils

pub fn update(msg, model) {
  case msg {
    mm.ServerCreatedImmunization(Ok(imm), _) -> server_created(model, imm)
    mm.ServerCreatedImmunization(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerUpdatedImmunization(Ok(imm), _) -> server_updated(model, imm)
    mm.ServerUpdatedImmunization(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerDeletedImmunization(Ok(_)) -> #(model, effect.none())
    mm.ServerDeletedImmunization(Error(_)) -> #(model, effect.none())
    mm.UserClickedCreateImmunization -> edit(model, None)
    mm.UserClickedEditImmunization(id) -> edit(model, Some(id))
    mm.UserClickedDeleteImmunization(id) -> delete(model, id)
    mm.UserClickedCloseImmunizationForm -> close_form(model)
    mm.UserSubmittedImmunizationForm(Ok(new_imm)) -> submit(model, new_imm)
    mm.UserSubmittedImmunizationForm(Error(err)) -> form_errors(model, err)
  }
}

pub fn server_created(
  model: Model,
  imm: r4us.Immunization,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_immunizations =
            list.append(data.patient_immunizations, [imm])
          mm.PatientLoadFound(mm.PatientData(..data, patient_immunizations:))
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
  updated_imm: r4us.Immunization,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_immunizations =
            data.patient_immunizations
            |> list.map(fn(old_imm) {
              case old_imm.id == updated_imm.id {
                True -> updated_imm
                False -> old_imm
              }
            })
          mm.PatientLoadFound(mm.PatientData(..data, patient_immunizations:))
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

pub fn edit(model: Model, edit_imm_id: Option(String)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id: pat_id, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          case edit_imm_id {
            Some(edit_imm_id) -> {
              case
                data.patient_immunizations
                |> list.find(fn(imm) { imm.id == Some(edit_imm_id) })
              {
                Error(_) -> #(model, effect.none())
                Ok(imm) -> {
                  immunization_schema(imm)
                  |> form.new
                  |> form.add_string(
                    "note",
                    utils.annotation_first_text(imm.note),
                  )
                  |> form.add_string(
                    "status",
                    r4us_valuesets.immunizationstatus_to_string(imm.status),
                  )
                  |> form.add_string(
                    "vaccine_code",
                    case imm.vaccine_code.coding {
                      [first, ..] -> option.unwrap(first.code, "")
                      [] -> ""
                    },
                  )
                  |> form.add_string("occurrence", case imm.occurrence {
                    r4us.ImmunizationOccurrenceDatetime(primitive_types.DateTime(
                      date:,
                      ..,
                    )) -> date |> primitive_types.date_to_string
                    r4us.ImmunizationOccurrenceString(s) -> s
                  })
                  |> form.add_string(
                    "lot_number",
                    option.unwrap(imm.lot_number, ""),
                  )
                  |> form.add_string("site", case imm.site {
                    None -> ""
                    Some(cc) -> utils.codeableconcept_to_string(cc)
                  })
                  |> form.add_string("id", edit_imm_id)
                  |> form_to_model(model, pat_id, patient)
                }
              }
            }
            None -> {
              let patient_ref = data.patient |> utils.patient_to_reference
              r4us.immunization_new(
                occurrence: r4us.ImmunizationOccurrenceString(""),
                patient: patient_ref,
                vaccine_code: r4us.codeableconcept_new(),
                status: r4us_valuesets.ImmunizationstatusCompleted,
              )
              |> immunization_schema
              |> form.new
              |> form_to_model(model, pat_id, patient)
            }
          }
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_to_model(imm_form, model, pat_id, patient) {
  let imm_form =
    imm_form
    |> mm.FormStateSome
    |> mm.PatientImmunizations
  let route = mm.RoutePatient(id: pat_id, patient:, page: imm_form)
  #(Model(..model, route:), effect.none())
}

pub fn server_error(
  model: Model,
  submitted_form: Form(r4us.Immunization),
  err: r4us_rsvp.Err,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let imm_form =
        submitted_form
        |> form.add_error(
          "vaccine_code",
          form.CustomError("Server error: " <> utils.err_to_string(err)),
        )
        |> mm.FormStateSome
        |> mm.PatientImmunizations
      let route = mm.RoutePatient(id:, patient:, page: imm_form)
      #(Model(..model, route:), effect.none())
    }
  }
}

pub fn submit(model: Model, form_imm: r4us.Immunization) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let submitted_form = case page {
            mm.PatientImmunizations(mm.FormStateSome(f)) -> f
            _ -> form.new(immunization_schema(form_imm))
          }
          let imm_with_patient =
            r4us.Immunization(
              ..form_imm,
              patient: data.patient |> utils.patient_to_reference,
            )
          let effect = case imm_with_patient.id {
            None ->
              r4us_rsvp.immunization_create(
                imm_with_patient,
                model.client,
                fn(result) {
                  mm.ServerCreatedImmunization(result, submitted_form)
                },
              )
            Some(_) ->
              r4us_rsvp.immunization_update(
                imm_with_patient,
                model.client,
                fn(result) {
                  mm.ServerUpdatedImmunization(result, submitted_form)
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
  let imm_form = mm.PatientImmunizations(formstate)
  let route = mm.RoutePatient(id:, patient:, page: imm_form)
  Model(..model, route:)
}

pub fn delete(model: Model, imm_id: String) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          case
            data.patient_immunizations
            |> list.find(fn(i) { i.id == Some(imm_id) })
          {
            Error(_) -> #(model, effect.none())
            Ok(imm) -> {
              let eff =
                r4us_rsvp.immunization_delete(
                  imm,
                  model.client,
                  mm.ServerDeletedImmunization,
                )
                |> result.unwrap(effect.none())
              let patient_immunizations =
                data.patient_immunizations
                |> list.filter(fn(i) { i.id != Some(imm_id) })
              let new_pat =
                mm.PatientLoadFound(
                  mm.PatientData(..data, patient_immunizations:),
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

pub fn form_errors(model: Model, err: Form(r4us.Immunization)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientImmunizations(mm.FormStateSome(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

pub fn immunization_schema(imm: r4us.Immunization) {
  use note_text <- form.field("note", form.parse_string)
  let note = case note_text {
    "" -> []
    _ -> [r4us.annotation_new(note_text)]
  }
  use status_str <- form.field("status", form.parse_string)
  let status = case r4us_valuesets.immunizationstatus_from_string(status_str) {
    Ok(s) -> s
    Error(_) -> r4us_valuesets.ImmunizationstatusCompleted
  }
  use vaccine_code <- form.field(
    "vaccine_code",
    form.parse(fn(input) {
      let str = case input {
        [s, ..] -> s
        [] -> ""
      }
      case list.find(vaccinecodes.vaccine_codes, fn(entry) { entry.0 == str }) {
        Ok(#(code_val, display)) ->
          Ok(
            r4us.Codeableconcept(
              ..r4us.codeableconcept_new(),
              text: Some(display),
              coding: [
                utils.coding(
                  code: code_val,
                  system: "http://hl7.org/fhir/sid/cvx",
                  display:,
                ),
              ],
            ),
          )
        Error(_) -> Error(#(imm.vaccine_code, "Must choose a vaccine"))
      }
    }),
  )
  use occurrence <- form.field(
    "occurrence",
    form.parse(fn(input) {
      case input {
        [dt, ..] ->
          case dt {
            //not strictly needed to check "" but might be nicer error msg
            "" -> Error(#(imm.occurrence, "Date cannot be empty"))
            dt ->
              case primitive_types.parse_datetime(dt) {
                Ok(dt) -> Ok(r4us.ImmunizationOccurrenceDatetime(dt))
                Error(_) -> Error(#(imm.occurrence, "Invalid date"))
              }
          }
        [] -> Error(#(imm.occurrence, "Date cannot be empty"))
      }
    }),
  )
  use lot_number <- form.field(
    "lot_number",
    form.parse_optional(form.parse_string),
  )
  use site_str <- form.field("site", form.parse_string)
  let site = case site_str {
    "" -> None
    s -> Some(r4us.Codeableconcept(..r4us.codeableconcept_new(), text: Some(s)))
  }
  form.success(
    r4us.Immunization(
      ..imm,
      note:,
      status:,
      vaccine_code:,
      occurrence:,
      lot_number:,
      site:,
    ),
  )
}

pub fn view(
  pat: mm.PatientData,
  immunization_form: mm.FormState(r4us.Immunization),
) {
  let head =
    h.tr(
      [],
      utils.th_list([
        "vaccine",
        "status",
        "date",
        "lot number",
        "site",
        "notes",
        "",
      ]),
    )
  let spacer = [h.tr([a.class("border-b-4 border-slate-600")], [])]
  let grouped_rows =
    pat.patient_immunizations
    |> list.group(fn(imm) {
      case imm.vaccine_code.coding {
        [first, ..] -> option.unwrap(first.code, "")
        [] -> utils.codeableconcept_to_string(imm.vaccine_code)
      }
    })
    |> dict.to_list
    |> list.map(fn(group) {
      let #(_, doses) = group
      list.map(doses, fn(imm) {
        case imm.id {
          None -> element.none()
          Some(imm_id) ->
            h.tr([a.class("border-b border-slate-700")], [
              h.td([a.class("p-2")], [
                h.text(utils.codeableconcept_to_string(imm.vaccine_code)),
              ]),
              h.td([a.class("p-2")], [
                h.text(r4us_valuesets.immunizationstatus_to_string(imm.status)),
              ]),
              h.td([a.class("p-2")], [
                case imm.occurrence {
                  r4us.ImmunizationOccurrenceDatetime(d) ->
                    h.text(d |> primitive_types.datetime_to_string)
                  r4us.ImmunizationOccurrenceString(s) -> h.text(s)
                },
              ]),
              h.td([a.class("p-2")], [
                case imm.lot_number {
                  None -> element.none()
                  Some(ln) -> h.text(ln)
                },
              ]),
              h.td([a.class("p-2")], [
                case imm.site {
                  None -> element.none()
                  Some(s) -> h.text(utils.codeableconcept_to_string(s))
                },
              ]),
              h.td([a.class("p-2 max-w-xs truncate")], [
                h.text(utils.annotation_first_text(imm.note)),
              ]),
              h.td([a.class("p-2 flex gap-2")], [
                btn("Edit", on_click: mm.UserClickedEditImmunization(imm_id)),
                btn(
                  "Delete",
                  on_click: mm.UserClickedDeleteImmunization(imm_id),
                ),
              ]),
            ])
        }
      })
    })
    |> list.map(fn(group) { list.flatten([spacer, group]) })
    |> list.flatten
  [
    h.div([a.class("p-4 max-w-4xl h-full flex flex-col overflow-hidden")], [
      h.div([a.class("flex items-center gap-4 mb-4")], [
        h.h1([a.class("text-xl font-bold")], [h.text("Immunizations")]),
        btn(
          "Create New Immunization",
          on_click: mm.UserClickedCreateImmunization,
        ),
      ]),
      case immunization_form {
        mm.FormStateNone -> element.none()
        mm.FormStateLoading -> h.p([], [h.text("loading...")])
        mm.FormStateSome(imm_form) -> {
          let legend_text = case form.field_value(imm_form, "id") {
            "" -> "Create Immunization"
            _ -> {
              let code = form.field_value(imm_form, "vaccine_code")
              let display =
                vaccinecodes.vaccine_codes
                |> list.find(fn(entry) { entry.0 == code })
                |> result.map(fn(entry) { entry.1 })
                |> result.unwrap(code)
              "Edit " <> display
            }
          }
          h.form(
            [
              a.class("max-w-2xl mb-4 shrink-0"),
              event.on_submit(fn(values) {
                imm_form
                |> form.add_values(values)
                |> form.run
                |> mm.UserSubmittedImmunizationForm
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
                    imm_form,
                    name: "vaccine_code",
                    options: list.map(vaccinecodes.vaccine_codes, fn(entry) {
                      CodingOption(
                        code: entry.0,
                        display: entry.1,
                        system: "http://hl7.org/fhir/sid/cvx",
                      )
                    }),
                    label: "vaccine",
                  ),
                  view_form_select(
                    imm_form,
                    name: "status",
                    options: list.map(
                      [
                        r4us_valuesets.ImmunizationstatusCompleted,
                        r4us_valuesets.ImmunizationstatusEnteredinerror,
                        r4us_valuesets.ImmunizationstatusNotdone,
                      ],
                      r4us_valuesets.immunizationstatus_to_string,
                    ),
                    label: "status",
                  ),
                  view_form_input(
                    imm_form,
                    is: "date",
                    name: "occurrence",
                    label: "date given",
                  ),
                  view_form_input(
                    imm_form,
                    is: "text",
                    name: "lot_number",
                    label: "lot number",
                  ),
                  view_form_input(
                    imm_form,
                    is: "text",
                    name: "site",
                    label: "site",
                  ),
                  view_form_textarea(imm_form, name: "note", label: "note"),
                  h.div([a.class("w-full flex justify-end gap-2")], [
                    btn_cancel(
                      "Cancel",
                      on_click: mm.UserClickedCloseImmunizationForm,
                    ),
                    btn_nomsg("Save Immunization"),
                  ]),
                ],
              ),
            ],
          )
        }
      },
      h.div([a.class("overflow-auto flex-1 min-h-0")], [
        h.table([a.class("border-collapse border border-slate-700 w-full")], [
          h.thead([], [head]),
          h.tbody([], grouped_rows),
        ]),
      ]),
    ]),
  ]
}
