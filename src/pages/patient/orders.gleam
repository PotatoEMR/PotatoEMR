import components.{
  CodingOption, btn, btn_cancel, btn_nomsg, view_form_coding_select,
  view_form_input, view_form_select, view_form_textarea,
}
import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/float
import gleam/int
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
import terminology/medicationcodes
import utils
import colors

const dose_units: List(String) = ["mg", "g", "tablet", "mL"]

const frequency_options: List(String) = [
  "every 4 hours", "every 8 hours", "every 12 hours", "every day",
]

pub fn update(msg, model) {
  case msg {
    mm.ServerCreatedOrder(Ok(mr), _) -> server_created(model, mr)
    mm.ServerCreatedOrder(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerUpdatedOrder(Ok(mr), _) -> server_updated(model, mr)
    mm.ServerUpdatedOrder(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerDeletedOrder(Ok(_)) -> #(model, effect.none())
    mm.ServerDeletedOrder(Error(_)) -> #(model, effect.none())
    mm.UserClickedCreateOrder -> edit(model, None)
    mm.UserClickedEditOrder(id) -> edit(model, Some(id))
    mm.UserClickedDeleteOrder(id) -> delete(model, id)
    mm.UserClickedCloseOrderForm -> close_form(model)
    mm.UserSubmittedOrderForm(Ok(new_mr)) -> submit(model, new_mr)
    mm.UserSubmittedOrderForm(Error(err)) -> form_errors(model, err)
  }
}

pub fn server_created(
  model: Model,
  mr: r4us.Medicationrequest,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_medication_requests =
            list.append(data.patient_medication_requests, [mr])
          mm.PatientLoadFound(
            mm.PatientData(..data, patient_medication_requests:),
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
  updated: r4us.Medicationrequest,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_medication_requests =
            data.patient_medication_requests
            |> list.map(fn(old) {
              case old.id == updated.id {
                True -> updated
                False -> old
              }
            })
          mm.PatientLoadFound(
            mm.PatientData(..data, patient_medication_requests:),
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
                data.patient_medication_requests
                |> list.find(fn(mr) { mr.id == Some(edit_id) })
              {
                Error(_) -> #(model, effect.none())
                Ok(mr) -> {
                  let #(dose_value, dose_unit, frequency) =
                    medreq_to_form_strings(mr)
                  medreq_schema(mr)
                  |> form.new
                  |> form.add_string("code", case mr.medication {
                    r4us.MedicationrequestMedicationCodeableconcept(cc) ->
                      case cc.coding {
                        [first, ..] -> option.unwrap(first.code, "")
                        [] -> ""
                      }
                    _ -> ""
                  })
                  |> form.add_string(
                    "status",
                    r4us_valuesets.medicationrequeststatus_to_string(mr.status),
                  )
                  |> form.add_string(
                    "intent",
                    r4us_valuesets.medicationrequestintent_to_string(mr.intent),
                  )
                  |> form.add_string(
                    "note",
                    utils.annotation_first_text(mr.note),
                  )
                  |> form.add_string("authored_on", case mr.authored_on {
                    None -> ""
                    Some(d) -> d |> primitive_types.datetime_to_string
                  })
                  |> form.add_string("dose_value", dose_value)
                  |> form.add_string("dose_unit", dose_unit)
                  |> form.add_string("frequency", frequency)
                  |> form.add_string("id", edit_id)
                  |> form_to_model(model, pat_id, patient)
                }
              }
            None -> {
              let blank =
                r4us.medicationrequest_new(
                  subject: data.patient |> utils.patient_to_reference,
                  medication: r4us.MedicationrequestMedicationCodeableconcept(
                    r4us.codeableconcept_new(),
                  ),
                  intent: r4us_valuesets.MedicationrequestintentOrder,
                  status: r4us_valuesets.MedicationrequeststatusActive,
                )
              medreq_schema(blank)
              |> form.new
              |> form_to_model(model, pat_id, patient)
            }
          }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_to_model(order_form, model, pat_id, patient) {
  let order_form =
    order_form
    |> mm.FormStateSome
    |> mm.PatientOrders
  let route = mm.RoutePatient(id: pat_id, patient:, page: order_form)
  #(Model(..model, route:), effect.none())
}

pub fn server_error(
  model: Model,
  submitted_form: Form(r4us.Medicationrequest),
  err: r4us_rsvp.Err,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let order_form =
        submitted_form
        |> form.add_error(
          "code",
          form.CustomError("Server error: " <> utils.err_to_string(err)),
        )
        |> mm.FormStateSome
        |> mm.PatientOrders
      let route = mm.RoutePatient(id:, patient:, page: order_form)
      #(Model(..model, route:), effect.none())
    }
  }
}

pub fn submit(model: Model, form_mr: r4us.Medicationrequest) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let submitted_form = case page {
            mm.PatientOrders(mm.FormStateSome(f)) -> f
            _ -> form.new(medreq_schema(form_mr))
          }
          let mr_with_subject =
            r4us.Medicationrequest(
              ..form_mr,
              subject: data.patient |> utils.patient_to_reference,
            )
          let effect = case mr_with_subject.id {
            None ->
              r4us_rsvp.medicationrequest_create(
                mr_with_subject,
                model.client,
                fn(result) { mm.ServerCreatedOrder(result, submitted_form) },
              )
            Some(_) ->
              r4us_rsvp.medicationrequest_update(
                mr_with_subject,
                model.client,
                fn(result) { mm.ServerUpdatedOrder(result, submitted_form) },
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
  let order_form = mm.PatientOrders(formstate)
  let route = mm.RoutePatient(id:, patient:, page: order_form)
  Model(..model, route:)
}

pub fn delete(model: Model, mr_id: String) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) ->
          case
            data.patient_medication_requests
            |> list.find(fn(m) { m.id == Some(mr_id) })
          {
            Error(_) -> #(model, effect.none())
            Ok(mr) -> {
              let eff =
                r4us_rsvp.medicationrequest_delete(
                  mr,
                  model.client,
                  mm.ServerDeletedOrder,
                )
                |> result.unwrap(effect.none())
              let patient_medication_requests =
                data.patient_medication_requests
                |> list.filter(fn(m) { m.id != Some(mr_id) })
              let new_pat =
                mm.PatientLoadFound(
                  mm.PatientData(..data, patient_medication_requests:),
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

pub fn form_errors(model: Model, err: Form(r4us.Medicationrequest)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientOrders(mm.FormStateSome(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

pub fn medreq_schema(mr: r4us.Medicationrequest) {
  use medication <- form.field(
    "code",
    form.parse(fn(input) {
      let str = case input {
        [s, ..] -> s
        [] -> ""
      }
      case list.find(medicationcodes.medication_codes, fn(e) { e.0 == str }) {
        Ok(#(code_val, display)) ->
          Ok(r4us.MedicationrequestMedicationCodeableconcept(
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
        Error(_) -> Error(#(mr.medication, "Must choose a medication"))
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
      case r4us_valuesets.medicationrequeststatus_from_string(str) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(#(mr.status, "Must choose a status"))
      }
    }),
  )
  use intent <- form.field(
    "intent",
    form.parse(fn(input) {
      let str = case input {
        [s, ..] -> s
        [] -> ""
      }
      case r4us_valuesets.medicationrequestintent_from_string(str) {
        Ok(i) -> Ok(i)
        Error(_) -> Error(#(mr.intent, "Must choose an intent"))
      }
    }),
  )
  use note_text <- form.field("note", form.parse_string)
  let note = case note_text {
    "" -> []
    _ -> [r4us.annotation_new(note_text)]
  }
  use form_authored_on <- form.field(
    "authored_on",
    form.parse_optional(form.parse_string),
  )
  let authored_on = case form_authored_on {
    Some(d) ->
      case primitive_types.parse_datetime(d) {
        Ok(d) -> Some(d)
        Error(_) -> None
      }
    None -> None
  }
  use dose_value_str <- form.field("dose_value", form.parse_string)
  use dose_unit <- form.field("dose_unit", form.parse_string)
  use frequency_str <- form.field("frequency", form.parse_string)
  let dose_qty = case parse_dose_value(dose_value_str), dose_unit {
    Ok(v), unit if unit != "" ->
      Some(
        r4us.Quantity(..r4us.quantity_new(), value: Some(v), unit: Some(unit)),
      )
    _, _ -> None
  }
  let dose_and_rate = case dose_qty {
    Some(q) -> [
      r4us.DosageDoseandrate(
        id: None,
        extension: [],
        type_: None,
        dose: Some(r4us.DosageDoseandrateDoseQuantity(q)),
        rate: None,
      ),
    ]
    None -> []
  }
  let timing = frequency_to_timing(frequency_str)
  let dosage_instruction = case dose_and_rate, timing {
    [], None -> []
    _, _ -> [r4us.Dosage(..r4us.dosage_new(), dose_and_rate:, timing:)]
  }
  form.success(
    r4us.Medicationrequest(
      ..mr,
      medication:,
      status:,
      intent:,
      note:,
      authored_on:,
      dosage_instruction:,
    ),
  )
}

fn parse_dose_value(s: String) -> Result(Float, Nil) {
  case float.parse(s) {
    Ok(v) -> Ok(v)
    Error(_) -> int.parse(s) |> result.map(int.to_float)
  }
}

fn frequency_to_period(
  s: String,
) -> Option(#(Float, r4us_valuesets.Unitsoftime)) {
  case s {
    "every 4 hours" -> Some(#(4.0, r4us_valuesets.UnitsoftimeH))
    "every 8 hours" -> Some(#(8.0, r4us_valuesets.UnitsoftimeH))
    "every 12 hours" -> Some(#(12.0, r4us_valuesets.UnitsoftimeH))
    "every day" -> Some(#(1.0, r4us_valuesets.UnitsoftimeD))
    _ -> None
  }
}

fn frequency_to_timing(s: String) -> Option(r4us.Timing) {
  case frequency_to_period(s) {
    None -> None
    Some(#(period, unit)) ->
      Some(
        r4us.Timing(
          ..r4us.timing_new(),
          repeat: Some(
            r4us.TimingRepeat(
              ..r4us.timing_repeat_new(),
              frequency: Some(1),
              period: Some(period),
              period_unit: Some(unit),
            ),
          ),
        ),
      )
  }
}

fn period_to_frequency(
  period: Float,
  unit: r4us_valuesets.Unitsoftime,
) -> String {
  case unit, period {
    r4us_valuesets.UnitsoftimeH, 4.0 -> "every 4 hours"
    r4us_valuesets.UnitsoftimeH, 8.0 -> "every 8 hours"
    r4us_valuesets.UnitsoftimeH, 12.0 -> "every 12 hours"
    r4us_valuesets.UnitsoftimeD, 1.0 -> "every day"
    _, _ -> ""
  }
}

fn medreq_to_form_strings(
  mr: r4us.Medicationrequest,
) -> #(String, String, String) {
  case mr.dosage_instruction {
    [] -> #("", "", "")
    [d, ..] -> {
      let #(dv, du) = case d.dose_and_rate {
        [first, ..] ->
          case first.dose {
            Some(r4us.DosageDoseandrateDoseQuantity(q)) -> {
              let v = case q.value {
                Some(v) -> float.to_string(v)
                None -> ""
              }
              let u = option.unwrap(q.unit, "")
              #(v, u)
            }
            _ -> #("", "")
          }
        [] -> #("", "")
      }
      let f = case d.timing {
        Some(t) ->
          case t.repeat {
            Some(r) ->
              case r.period, r.period_unit {
                Some(p), Some(u) -> period_to_frequency(p, u)
                _, _ -> ""
              }
            None -> ""
          }
        None -> ""
      }
      #(dv, du, f)
    }
  }
}

pub fn dosage_to_string(dosage: r4us.Dosage) -> String {
  case dosage.text {
    Some(t) -> t
    None -> {
      let dose_str = case dosage.dose_and_rate {
        [first, ..] ->
          case first.dose {
            Some(r4us.DosageDoseandrateDoseQuantity(q)) -> quantity_to_string(q)
            _ -> ""
          }
        [] -> ""
      }
      let timing_str = case dosage.timing {
        Some(t) ->
          case t.repeat {
            Some(r) -> repeat_to_string(r)
            None -> ""
          }
        None -> ""
      }
      [dose_str, timing_str]
      |> list.filter(fn(s) { s != "" })
      |> string.join(" ")
    }
  }
}

fn quantity_to_string(q: r4us.Quantity) -> String {
  let v = case q.value {
    Some(v) -> float.to_string(v)
    None -> ""
  }
  let u = option.unwrap(q.unit, "")
  case v, u {
    "", "" -> ""
    "", u -> u
    v, "" -> v
    v, u -> v <> " " <> u
  }
}

fn repeat_to_string(r: r4us.TimingRepeat) -> String {
  case r.period, r.period_unit {
    Some(p), Some(u) ->
      "every "
      <> float.to_string(p)
      <> " "
      <> r4us_valuesets.unitsoftime_to_string(u)
    _, _ -> ""
  }
}

fn dosages_to_string(dosages: List(r4us.Dosage)) -> String {
  dosages |> list.map(dosage_to_string) |> string.join("; ")
}

pub fn view(
  pat: mm.PatientData,
  order_form: mm.FormState(r4us.Medicationrequest),
) {
  let head =
    h.tr(
      [],
      utils.th_list([
        "medication",
        "dosage",
        "status",
        "intent",
        "authored",
        "notes",
        "",
      ]),
    )
  let rows =
    list.map(pat.patient_medication_requests, fn(mr) {
      case mr.id {
        None -> element.none()
        Some(mr_id) ->
          h.tr([a.class("border-b " <> colors.border_slate_700)], [
            h.td([a.class("p-2")], [
              case mr.medication {
                r4us.MedicationrequestMedicationCodeableconcept(cc) ->
                  h.p([], [h.text(utils.codeableconcept_to_string(cc))])
                r4us.MedicationrequestMedicationReference(ref) ->
                  h.p([], [h.text(option.unwrap(ref.display, ""))])
              },
            ]),
            h.td([a.class("p-2")], [
              h.text(dosages_to_string(mr.dosage_instruction)),
            ]),
            h.td([a.class("p-2")], [
              h.text(r4us_valuesets.medicationrequeststatus_to_string(mr.status)),
            ]),
            h.td([a.class("p-2")], [
              h.text(r4us_valuesets.medicationrequestintent_to_string(mr.intent)),
            ]),
            h.td([a.class("p-2")], [
              case mr.authored_on {
                None -> element.none()
                Some(d) -> h.text(d |> primitive_types.datetime_to_string)
              },
            ]),
            h.td([a.class("p-2 max-w-xs truncate")], [
              h.text(utils.annotation_first_text(mr.note)),
            ]),
            h.td([a.class("p-2 flex gap-2")], [
              btn("Edit", on_click: mm.UserClickedEditOrder(mr_id)),
              btn("Delete", on_click: mm.UserClickedDeleteOrder(mr_id)),
            ]),
          ])
      }
    })
  [
    h.div([a.class("p-4 max-w-5xl")], [
      h.div([a.class("flex items-center gap-4 mb-4")], [
        h.h1([a.class("text-xl font-bold")], [h.text("Orders")]),
        btn("Create New Order", on_click: mm.UserClickedCreateOrder),
      ]),
      h.table([a.class("border-collapse border " <> colors.border_slate_700)], [
        h.thead([], [head]),
        h.tbody([], rows),
      ]),
      case order_form {
        mm.FormStateNone -> element.none()
        mm.FormStateLoading -> h.p([], [h.text("loading...")])
        mm.FormStateSome(order_form) -> {
          let legend_text = case form.field_value(order_form, "id") {
            "" -> "Create Order"
            _ -> {
              let code = form.field_value(order_form, "code")
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
                order_form
                |> form.add_values(values)
                |> form.run
                |> mm.UserSubmittedOrderForm
              }),
            ],
            [
              h.fieldset(
                [
                  a.class(
                    "border " <> colors.border_slate_700 <> " rounded-lg p-4 flex flex-row flex-wrap gap-4",
                  ),
                ],
                [
                  h.legend([a.class("px-2 text-sm font-bold " <> colors.text_slate_200)], [
                    h.text(legend_text),
                  ]),
                  view_form_coding_select(
                    order_form,
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
                  view_form_input(
                    order_form,
                    is: "number",
                    name: "dose_value",
                    label: "dose",
                  ),
                  view_form_select(
                    order_form,
                    name: "dose_unit",
                    options: dose_units,
                    label: "unit",
                  ),
                  view_form_select(
                    order_form,
                    name: "frequency",
                    options: frequency_options,
                    label: "frequency",
                  ),
                  view_form_select(
                    order_form,
                    name: "status",
                    options: [
                      r4us_valuesets.MedicationrequeststatusActive,
                      r4us_valuesets.MedicationrequeststatusOnhold,
                      r4us_valuesets.MedicationrequeststatusCancelled,
                      r4us_valuesets.MedicationrequeststatusCompleted,
                      r4us_valuesets.MedicationrequeststatusStopped,
                      r4us_valuesets.MedicationrequeststatusDraft,
                    ]
                      |> list.map(
                        r4us_valuesets.medicationrequeststatus_to_string,
                      ),
                    label: "status",
                  ),
                  view_form_select(
                    order_form,
                    name: "intent",
                    options: [
                      r4us_valuesets.MedicationrequestintentProposal,
                      r4us_valuesets.MedicationrequestintentPlan,
                      r4us_valuesets.MedicationrequestintentOrder,
                      r4us_valuesets.MedicationrequestintentOriginalorder,
                    ]
                      |> list.map(
                        r4us_valuesets.medicationrequestintent_to_string,
                      ),
                    label: "intent",
                  ),
                  view_form_input(
                    order_form,
                    is: "date",
                    name: "authored_on",
                    label: "authored",
                  ),
                  view_form_textarea(order_form, name: "note", label: "note"),
                  h.div([a.class("w-full flex justify-end gap-2")], [
                    btn_cancel("Cancel", on_click: mm.UserClickedCloseOrderForm),
                    btn_nomsg("Save Order"),
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
