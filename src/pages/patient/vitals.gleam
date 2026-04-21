import components.{btn, btn_cancel, btn_nomsg}
import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import utils

const vital_columns: List(#(String, String, String)) = [
  #("8867-4", "Heart Rate (/min)", "heart_rate"),
  #("9279-1", "Resp Rate (/min)", "respiratory_rate"),
  #("2708-6", "O2 Sat (%)", "oxygen_saturation"),
  #("8310-5", "Temp (Cel)", "body_temperature"),
  #("8302-2", "Height (cm)", "body_height"),
  #("9843-4", "Head Circ (cm)", "head_circumference"),
  #("29463-7", "Weight (kg)", "body_weight"),
  #("39156-5", "BMI (kg/m2)", "bmi"),
  #("85354-9", "BP (mmHg)", ""),
]

const time_column_style = "width: 13rem; min-width: 13rem; max-width: 13rem; height: 3rem; min-height: 3rem; max-height: 3rem; padding: 0; vertical-align: middle;"

const time_column_inner_style = "width: 13rem; min-width: 13rem; max-width: 13rem; min-height: 3rem; max-height: 3rem; padding: 0.5rem; box-sizing: border-box; overflow: hidden;"

const row_style = "height: 3rem; min-height: 3rem; max-height: 3rem;"

const header_row_style = "height: 4.5rem; min-height: 4.5rem; max-height: 4.5rem;"

const label_cell_style = "height: 3rem; min-height: 3rem; max-height: 3rem; width: 14rem; min-width: 14rem; max-width: 14rem; padding: 0; vertical-align: middle;"

const header_label_cell_style = "height: 4.5rem; min-height: 4.5rem; max-height: 4.5rem; width: 14rem; min-width: 14rem; max-width: 14rem; padding: 0; vertical-align: middle;"

const header_time_column_style = "width: 13rem; min-width: 13rem; max-width: 13rem; height: 4.5rem; min-height: 4.5rem; max-height: 4.5rem; padding: 0; vertical-align: top;"

const header_time_column_inner_style = "width: 13rem; min-width: 13rem; max-width: 13rem; min-height: 4.5rem; max-height: 4.5rem; padding: 0.5rem; box-sizing: border-box; overflow: hidden;"

fn is_vital_signs(obs: r4us.Observation) -> Bool {
  list.any(obs.category, fn(cat) {
    list.any(cat.coding, fn(c) { c.code == Some("vital-signs") })
  })
}

fn obs_code(obs: r4us.Observation) -> String {
  case obs.code.coding {
    [] -> ""
    [first, ..] -> option.unwrap(first.code, "")
  }
}

fn obs_time(obs: r4us.Observation) -> String {
  let raw = case obs.effective {
    Some(r4us.ObservationEffectiveDatetime(effective: dt)) ->
      primitive_types.datetime_to_string(dt)
    Some(r4us.ObservationEffectivePeriod(effective: p)) ->
      case p.start {
        Some(s) -> primitive_types.datetime_to_string(s)
        None -> ""
      }
    _ -> ""
  }
  format_time(raw)
}

fn format_time(s: String) -> String {
  let trimmed = case string.length(s) >= 19 {
    True -> string.slice(s, 0, 19)
    False -> s
  }
  string.replace(trimmed, "T", " ")
}

fn format_float(f: Float) -> String {
  f |> float.to_precision(2) |> float.to_string
}

fn fixed_time_column_attrs(extra_class: String) {
  [
    a.class(extra_class),
    a.attribute("style", time_column_style),
  ]
}

fn fixed_time_column_inner(children: List(Element(msg))) -> Element(msg) {
  h.div(
    [
      a.class("box-border"),
      a.attribute("style", time_column_inner_style),
    ],
    children,
  )
}

fn fixed_header_time_column_attrs(extra_class: String) {
  [
    a.class(extra_class),
    a.attribute("style", header_time_column_style),
  ]
}

fn fixed_header_time_column_inner(children: List(Element(msg))) -> Element(msg) {
  h.div(
    [
      a.class("box-border"),
      a.attribute("style", header_time_column_inner_style),
    ],
    children,
  )
}

fn fixed_row_attrs(extra_class: String) {
  [
    a.class(extra_class),
    a.attribute("style", row_style),
  ]
}

fn fixed_header_row_attrs(extra_class: String) {
  [
    a.class(extra_class),
    a.attribute("style", header_row_style),
  ]
}

fn fixed_label_cell(label: String) -> Element(msg) {
  h.th(
    [
      a.class("text-left border border-slate-700"),
      a.attribute("style", label_cell_style),
    ],
    [
      h.div(
        [
          a.class(
            "h-full px-2 overflow-hidden whitespace-nowrap flex items-center",
          ),
        ],
        [
          h.text(label),
        ],
      ),
    ],
  )
}

fn fixed_blank_header_cell() -> Element(msg) {
  h.th(
    [
      a.class("border border-slate-700"),
      a.attribute("style", header_label_cell_style),
    ],
    [h.div([a.class("h-full")], [])],
  )
}

fn fixed_blank_footer_cell() -> Element(msg) {
  h.td(
    [
      a.class("border border-slate-700"),
      a.attribute("style", label_cell_style),
    ],
    [h.div([a.class("h-full")], [])],
  )
}

fn quantity_to_string(q: r4us.Quantity) -> String {
  let v = case q.value {
    Some(v) -> format_float(v)
    None -> ""
  }
  case q.unit {
    Some(u) -> v <> " " <> u
    None -> v
  }
}

fn obs_value_string(obs: r4us.Observation) -> String {
  case obs.value {
    Some(r4us.ObservationValueQuantity(value: q)) -> quantity_to_string(q)
    Some(r4us.ObservationValueString(value: s)) -> s
    Some(r4us.ObservationValueInteger(value: i)) -> int.to_string(i)
    _ -> ""
  }
}

fn find_component_value(
  comps: List(r4us.ObservationComponent),
  code: String,
) -> String {
  case
    list.find(comps, fn(c) {
      list.any(c.code.coding, fn(cc) { cc.code == Some(code) })
    })
  {
    Error(_) -> ""
    Ok(c) ->
      case c.value {
        Some(r4us.ObservationComponentValueQuantity(value: q)) ->
          case q.value {
            Some(v) -> format_float(v)
            None -> ""
          }
        _ -> ""
      }
  }
}

fn bp_value_string(obs: r4us.Observation) -> String {
  let sys = find_component_value(obs.component, "8480-6")
  let dia = find_component_value(obs.component, "8462-4")
  sys <> "/" <> dia
}

fn cell_value(obs: r4us.Observation, code: String) -> String {
  case code {
    "85354-9" -> bp_value_string(obs)
    _ -> obs_value_string(obs)
  }
}

pub fn update(msg, model: Model) {
  case msg {
    mm.UserClickedCreateVitals -> open_form(model)
    mm.UserClickedEditVitalsColumn(time_key) -> open_edit(model, time_key)
    mm.UserClickedDeleteVitalsColumn(time_key) -> delete_column(model, time_key)
    mm.UserClickedCloseVitalsForm -> set_form_state(model, mm.FormStateNone)
    mm.UserSubmittedVitalsForm(Ok(observations)) -> submit(model, observations)
    mm.UserSubmittedVitalsForm(Error(err)) ->
      set_form_state(model, mm.FormStateSome(err))
    mm.ServerReturnedVitalsBundle(Ok(bundle), _) ->
      bundle_returned(model, bundle)
    mm.ServerReturnedVitalsBundle(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerReturnedVitalsDelete(time_key, Ok(_)) ->
      delete_column_done(model, time_key)
    mm.ServerReturnedVitalsDelete(_, Error(_)) ->
      set_form_state(model, mm.FormStateNone)
  }
}

fn delete_column(model: Model, time_key: String) {
  case model.route {
    mm.RoutePatient(patient: mm.PatientLoadFound(data:), ..) -> {
      let ids =
        data.patient_observations
        |> list.filter(fn(o) { is_vital_signs(o) && obs_time(o) == time_key })
        |> list.filter_map(fn(o) {
          case o.id {
            Some(id) -> Ok(id)
            None -> Error(Nil)
          }
        })
      case ids {
        [] -> #(model, effect.none())
        _ -> {
          let reqs =
            list.map(ids, fn(id) {
              r4us_sansio.any_delete_req(id, "Observation", model.client)
            })
          let eff =
            r4us_rsvp.batch(
              reqs,
              r4us_sansio.Transaction,
              model.client,
              fn(res) { mm.ServerReturnedVitalsDelete(time_key, res) },
            )
          let #(model, _) = set_form_state(model, mm.FormStateLoading)
          #(model, eff)
        }
      }
    }
    _ -> #(model, effect.none())
  }
}

fn delete_column_done(model: Model, time_key: String) {
  case model.route {
    mm.RoutePatient(id:, patient: mm.PatientLoadFound(data:), page: _) -> {
      let patient_observations =
        list.filter(data.patient_observations, fn(o) {
          case is_vital_signs(o) && obs_time(o) == time_key {
            True -> False
            False -> True
          }
        })
      let patient =
        mm.PatientLoadFound(mm.PatientData(..data, patient_observations:))
      let route =
        mm.RoutePatient(id:, patient:, page: mm.PatientVitals(mm.FormStateNone))
      #(Model(..model, route:), effect.none())
    }
    _ -> set_form_state(model, mm.FormStateNone)
  }
}

fn open_form(model: Model) {
  case patient_ref(model) {
    None -> #(model, effect.none())
    Some(ref) -> {
      let f = vitals_schema(ref, []) |> form.new
      set_form_state(model, mm.FormStateSome(f))
    }
  }
}

fn open_edit(model: Model, time_key: String) {
  case patient_ref(model), model.route {
    Some(ref), mm.RoutePatient(patient: mm.PatientLoadFound(data:), ..) -> {
      let existing =
        data.patient_observations
        |> list.filter(fn(o) { is_vital_signs(o) && obs_time(o) == time_key })
      let f =
        vitals_schema(ref, existing)
        |> form.new
        |> prefill_edit_form(existing, time_key)
      set_form_state(model, mm.FormStateSome(f))
    }
    _, _ -> #(model, effect.none())
  }
}

fn prefill_edit_form(
  f: Form(a),
  existing: List(r4us.Observation),
  time_key: String,
) -> Form(a) {
  let f = form.add_string(f, "column_time", time_key)
  let dt_str = case existing {
    [first, ..] ->
      case first.effective {
        Some(r4us.ObservationEffectiveDatetime(effective: dt)) ->
          primitive_types.datetime_to_string(dt) |> string.slice(0, 16)
        _ -> ""
      }
    [] -> ""
  }
  let f = form.add_string(f, "effective_datetime", dt_str)
  let simple_fields = [
    #("8867-4", "heart_rate"),
    #("9279-1", "respiratory_rate"),
    #("2708-6", "oxygen_saturation"),
    #("8310-5", "body_temperature"),
    #("8302-2", "body_height"),
    #("9843-4", "head_circumference"),
    #("29463-7", "body_weight"),
    #("39156-5", "bmi"),
  ]
  let f =
    list.fold(simple_fields, f, fn(acc, field) {
      let #(code, name) = field
      case list.find(existing, fn(o) { obs_code(o) == code }) {
        Ok(obs) ->
          case obs.value {
            Some(r4us.ObservationValueQuantity(value: q)) ->
              case q.value {
                Some(v) -> form.add_string(acc, name, format_float(v))
                None -> acc
              }
            _ -> acc
          }
        Error(_) -> acc
      }
    })
  case list.find(existing, fn(o) { obs_code(o) == "85354-9" }) {
    Ok(bp_obs) ->
      f
      |> form.add_string(
        "systolic",
        find_component_value(bp_obs.component, "8480-6"),
      )
      |> form.add_string(
        "diastolic",
        find_component_value(bp_obs.component, "8462-4"),
      )
    Error(_) -> f
  }
}

fn patient_ref(model: Model) -> Option(r4us.Reference) {
  case model.route {
    mm.RoutePatient(patient: mm.PatientLoadFound(data:), id: _, page: _) ->
      Some(utils.patient_to_reference(data.patient))
    _ -> None
  }
}

fn set_form_state(model: Model, formstate: mm.FormState(List(r4us.Observation))) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page: _) -> {
      let route =
        mm.RoutePatient(id:, patient:, page: mm.PatientVitals(formstate))
      #(Model(..model, route:), effect.none())
    }
  }
}

fn submit(model: Model, observations: List(r4us.Observation)) {
  case observations {
    [] -> set_form_state(model, mm.FormStateNone)
    _ -> {
      let submitted_form = case model.route {
        mm.RoutePatient(page: mm.PatientVitals(mm.FormStateSome(f)), ..) -> f
        _ -> form.new(vitals_schema(r4us.reference_new(), []))
      }
      let reqs =
        list.filter_map(observations, fn(obs) {
          case obs.id {
            None -> Ok(r4us_sansio.observation_create_req(obs, model.client))
            Some(_) -> r4us_sansio.observation_update_req(obs, model.client)
          }
        })
      let eff =
        r4us_rsvp.batch(reqs, r4us_sansio.Transaction, model.client, fn(result) {
          mm.ServerReturnedVitalsBundle(result, submitted_form)
        })
      let #(model, _) = set_form_state(model, mm.FormStateLoading)
      #(model, eff)
    }
  }
}

fn server_error(
  model: Model,
  submitted_form: Form(List(r4us.Observation)),
  err: r4us_rsvp.Err,
) {
  let f =
    submitted_form
    |> form.add_error(
      "effective_datetime",
      form.CustomError("Server error: " <> utils.err_to_string(err)),
    )
  set_form_state(model, mm.FormStateSome(f))
}

fn bundle_returned(model: Model, bundle: r4us.Bundle) {
  echo bundle
  let returned_obs =
    list.filter_map(bundle.entry, fn(entry) {
      case entry.resource {
        Some(r4us.ResourceObservation(obs)) -> Ok(obs)
        _ -> Error(Nil)
      }
    })
  echo returned_obs
  case model.route {
    mm.RoutePatient(id:, patient: mm.PatientLoadFound(data:), page: _) -> {
      let returned_ids =
        list.filter_map(returned_obs, fn(o) {
          case o.id {
            Some(id) -> Ok(id)
            None -> Error(Nil)
          }
        })
      let kept =
        list.filter(data.patient_observations, fn(o) {
          case o.id {
            Some(id) -> list.contains(returned_ids, id) == False
            None -> True
          }
        })
      let patient_observations = list.append(kept, returned_obs)
      let patient =
        mm.PatientLoadFound(mm.PatientData(..data, patient_observations:))
      let route =
        mm.RoutePatient(id:, patient:, page: mm.PatientVitals(mm.FormStateNone))
      #(Model(..model, route:), effect.none())
    }
    _ -> set_form_state(model, mm.FormStateNone)
  }
}

const vital_signs_category_system = "http://terminology.hl7.org/CodeSystem/observation-category"

const loinc_system = "http://loinc.org"

const ucum_system = "http://unitsofmeasure.org"

fn vital_category() -> r4us.Codeableconcept {
  r4us.Codeableconcept(..r4us.codeableconcept_new(), coding: [
    utils.coding(
      code: "vital-signs",
      system: vital_signs_category_system,
      display: "Vital Signs",
    ),
  ])
}

fn loinc_cc(code: String, display: String) -> r4us.Codeableconcept {
  r4us.Codeableconcept(
    ..r4us.codeableconcept_new(),
    text: Some(display),
    coding: [utils.coding(code: code, system: loinc_system, display: display)],
  )
}

fn ucum_qty(value: Float, unit: String) -> r4us.Quantity {
  r4us.Quantity(
    ..r4us.quantity_new(),
    value: Some(value),
    unit: Some(unit),
    system: Some(ucum_system),
    code: Some(unit),
  )
}

fn parse_required_datetime() {
  form.parse(fn(inputs) {
    let s = case inputs {
      [first, ..] -> first
      [] -> ""
    }
    let zero = primitive_types.DateTime(primitive_types.Year(1970), None)
    case s {
      "" -> Error(#(zero, "must not be empty"))
      _ ->
        case primitive_types.parse_datetime(normalize_datetime(s)) {
          Ok(dt) -> Ok(dt)
          Error(_) -> Error(#(zero, "must be a valid datetime"))
        }
    }
  })
}

fn normalize_datetime(s: String) -> String {
  case string.length(s) {
    16 -> s <> ":00Z"
    19 -> s <> "Z"
    _ -> s
  }
}

fn make_quantity_obs(
  existing: List(r4us.Observation),
  patient_ref: r4us.Reference,
  effective: Option(r4us.ObservationEffective),
  code: String,
  display: String,
  unit: String,
  value: Float,
) -> r4us.Observation {
  let base = case list.find(existing, fn(o) { obs_code(o) == code }) {
    Ok(e) -> e
    Error(_) ->
      r4us.observation_new(
        code: loinc_cc(code, display),
        status: r4us_valuesets.ObservationstatusFinal,
      )
  }
  r4us.Observation(
    ..base,
    code: loinc_cc(code, display),
    category: [vital_category()],
    subject: Some(patient_ref),
    effective:,
    value: Some(r4us.ObservationValueQuantity(ucum_qty(value, unit))),
  )
}

fn bp_component(code: String, display: String, value: Float) {
  r4us.ObservationComponent(
    ..r4us.observation_component_new(code: loinc_cc(code, display)),
    value: Some(
      r4us.ObservationComponentValueQuantity(ucum_qty(value, "mm[Hg]")),
    ),
  )
}

fn make_bp_obs(
  existing: List(r4us.Observation),
  patient_ref: r4us.Reference,
  effective: Option(r4us.ObservationEffective),
  systolic: Option(Float),
  diastolic: Option(Float),
) -> r4us.Observation {
  let sys_comp =
    option.map(systolic, bp_component("8480-6", "Systolic blood pressure", _))
  let dia_comp =
    option.map(diastolic, bp_component("8462-4", "Diastolic blood pressure", _))
  let components = [sys_comp, dia_comp] |> option.values
  let base = case list.find(existing, fn(o) { obs_code(o) == "85354-9" }) {
    Ok(e) -> e
    Error(_) ->
      r4us.observation_new(
        code: loinc_cc(
          "85354-9",
          "Blood pressure panel with all children optional",
        ),
        status: r4us_valuesets.ObservationstatusFinal,
      )
  }
  r4us.Observation(
    ..base,
    code: loinc_cc("85354-9", "Blood pressure panel with all children optional"),
    category: [vital_category()],
    subject: Some(patient_ref),
    effective:,
    component: components,
  )
}

fn vitals_schema(patient_ref: r4us.Reference, existing: List(r4us.Observation)) {
  use dt <- form.field("effective_datetime", parse_required_datetime())
  let effective = Some(r4us.ObservationEffectiveDatetime(dt))
  use heart_rate <- form.field(
    "heart_rate",
    form.parse_optional(form.parse_float),
  )
  use respiratory_rate <- form.field(
    "respiratory_rate",
    form.parse_optional(form.parse_float),
  )
  use oxygen_saturation <- form.field(
    "oxygen_saturation",
    form.parse_optional(form.parse_float),
  )
  use body_temperature <- form.field(
    "body_temperature",
    form.parse_optional(form.parse_float),
  )
  use body_height <- form.field(
    "body_height",
    form.parse_optional(form.parse_float),
  )
  use head_circumference <- form.field(
    "head_circumference",
    form.parse_optional(form.parse_float),
  )
  use body_weight <- form.field(
    "body_weight",
    form.parse_optional(form.parse_float),
  )
  use bmi <- form.field("bmi", form.parse_optional(form.parse_float))
  use systolic <- form.field("systolic", form.parse_optional(form.parse_float))
  use diastolic <- form.field(
    "diastolic",
    form.parse_optional(form.parse_float),
  )

  let simple = [
    #(heart_rate, "8867-4", "Heart rate", "/min"),
    #(respiratory_rate, "9279-1", "Respiratory rate", "/min"),
    #(oxygen_saturation, "2708-6", "Oxygen saturation in Arterial blood", "%"),
    #(body_temperature, "8310-5", "Body temperature", "Cel"),
    #(body_height, "8302-2", "Body height", "cm"),
    #(
      head_circumference,
      "9843-4",
      "Head Occipital-frontal circumference",
      "cm",
    ),
    #(body_weight, "29463-7", "Body weight", "kg"),
    #(bmi, "39156-5", "Body mass index (BMI) [Ratio]", "kg/m2"),
  ]

  let simple_obs =
    list.filter_map(simple, fn(t) {
      case t.0 {
        Some(v) ->
          Ok(make_quantity_obs(
            existing,
            patient_ref,
            effective,
            t.1,
            t.2,
            t.3,
            v,
          ))
        None -> Error(Nil)
      }
    })

  let bp_obs = case systolic, diastolic {
    None, None -> []
    _, _ -> [make_bp_obs(existing, patient_ref, effective, systolic, diastolic)]
  }

  form.success(list.append(simple_obs, bp_obs))
}

pub fn view(
  data: mm.PatientData,
  vitals_form: mm.FormState(List(r4us.Observation)),
) -> List(Element(mm.SubmsgVitals)) {
  let vitals =
    data.patient_observations
    |> list.filter(is_vital_signs)
    |> list.filter(fn(o) { obs_code(o) != "85353-1" })

  let groups =
    list.fold(vitals, dict.new(), fn(acc, obs) {
      dict.upsert(acc, obs_time(obs), fn(existing) {
        case existing {
          Some(xs) -> [obs, ..xs]
          None -> [obs]
        }
      })
    })

  let time_groups =
    groups
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(b.0, a.0) })

  let form_opt = case vitals_form {
    mm.FormStateSome(f) -> Some(f)
    _ -> None
  }

  let edit_time = case form_opt {
    Some(f) -> form.field_value(f, "column_time")
    None -> ""
  }
  let is_editing = edit_time != ""
  let is_creating = case form_opt {
    Some(_) -> edit_time == ""
    None -> False
  }

  let time_header_cells =
    list.map(time_groups, fn(pair) {
      case form_opt, pair.0 == edit_time && is_editing {
        Some(f), True -> form_datetime_cell(f)
        _, _ ->
          h.th(
            fixed_header_time_column_attrs(
              "p-2 text-left border border-slate-700",
            ),
            [
              fixed_header_time_column_inner([
                h.div(
                  [
                    a.class(
                      "h-full overflow-hidden whitespace-nowrap flex items-center",
                    ),
                  ],
                  [
                    h.text(pair.0),
                  ],
                ),
              ]),
            ],
          )
      }
    })
  let form_header_cell = case is_creating, form_opt {
    True, Some(f) -> [form_datetime_cell(f)]
    _, _ -> []
  }
  let head =
    h.tr(fixed_header_row_attrs(""), [
      fixed_blank_header_cell(),
      ..list.append(form_header_cell, time_header_cells)
    ])

  let rows =
    list.map(vital_columns, fn(col) {
      let #(code, label, field_name) = col
      let form_input_cells = case is_creating, form_opt {
        True, Some(f) -> [form_value_cell(f, code, field_name)]
        _, _ -> []
      }
      let time_cells =
        list.map(time_groups, fn(pair) {
          case form_opt, pair.0 == edit_time && is_editing {
            Some(f), True -> form_value_cell(f, code, field_name)
            _, _ -> {
              let val = case list.find(pair.1, fn(o) { obs_code(o) == code }) {
                Ok(obs) -> cell_value(obs, code)
                Error(_) -> ""
              }
              h.td(
                fixed_time_column_attrs("p-2 text-left border border-slate-700"),
                [
                  fixed_time_column_inner([
                    h.div(
                      [
                        a.class(
                          "h-full overflow-hidden whitespace-nowrap flex items-center",
                        ),
                      ],
                      [
                        h.text(val),
                      ],
                    ),
                  ]),
                ],
              )
            }
          }
        })
      h.tr(fixed_row_attrs("border-b border-slate-700"), [
        fixed_label_cell(label),
        ..list.append(form_input_cells, time_cells)
      ])
    })

  let save_cancel =
    fixed_time_column_inner([
      h.div([a.class("flex gap-2 justify-end overflow-hidden")], [
        btn_cancel("Cancel", on_click: mm.UserClickedCloseVitalsForm),
        btn_nomsg("Save"),
      ]),
    ])

  let form_footer_cell = case is_creating {
    True -> [
      h.td(fixed_time_column_attrs("p-2 border border-slate-700"), [save_cancel]),
    ]
    False -> []
  }
  let time_footer_cells =
    list.map(time_groups, fn(pair) {
      let is_this_edit = pair.0 == edit_time && is_editing
      let content = case is_this_edit, form_opt {
        True, _ -> [save_cancel]
        False, Some(_) -> []
        False, None -> [
          fixed_time_column_inner([
            h.div([a.class("flex gap-2 overflow-hidden")], [
              btn("Edit", on_click: mm.UserClickedEditVitalsColumn(pair.0)),
              btn("Delete", on_click: mm.UserClickedDeleteVitalsColumn(pair.0)),
            ]),
          ]),
        ]
      }
      h.td(fixed_time_column_attrs("p-2 border border-slate-700"), content)
    })
  let footer_rows = [
    h.tr(fixed_row_attrs(""), [
      fixed_blank_footer_cell(),
      ..list.append(form_footer_cell, time_footer_cells)
    ]),
  ]

  let table =
    h.table([a.class("border-collapse border border-slate-700 table-fixed")], [
      h.thead([], [head]),
      h.tbody([], rows),
      h.tfoot([], footer_rows),
    ])

  let wrapped = case form_opt {
    Some(f) ->
      h.form(
        [
          event.on_submit(fn(values) {
            f
            |> form.add_values(values)
            |> form.run
            |> mm.UserSubmittedVitalsForm
          }),
        ],
        [table],
      )
    None -> table
  }

  [
    h.div([a.class("p-4")], [
      h.div([a.class("flex items-center gap-4 mb-4")], [
        h.h1([a.class("text-xl font-bold")], [h.text("Vital Signs")]),
        btn(
          "Create New Vital Signs Panel",
          on_click: mm.UserClickedCreateVitals,
        ),
      ]),
      h.div([a.class("overflow-x-auto")], [wrapped]),
    ]),
  ]
}

fn form_datetime_cell(f: Form(a)) -> Element(mm.SubmsgVitals) {
  let name = "effective_datetime"
  let errors = form.field_error_messages(f, name)
  h.th(
    fixed_header_time_column_attrs(
      "p-2 text-left border border-slate-700 align-top",
    ),
    [
      fixed_header_time_column_inner([
        h.input([
          a.class("bg-slate-800 border border-slate-700 rounded"),
          a.attribute(
            "style",
            "display: block; width: 100%; max-width: 100%; min-width: 0; height: 2rem; box-sizing: border-box;",
          ),
          a.name(name),
          a.type_("datetime-local"),
          a.value(form.field_value(f, name)),
        ]),
        ..list.map(errors, fn(e) {
          h.div([a.class("text-xs text-red-400 leading-tight mt-1")], [
            h.text(e),
          ])
        })
      ]),
    ],
  )
}

fn form_value_cell(
  f: Form(a),
  code: String,
  field_name: String,
) -> Element(mm.SubmsgVitals) {
  case code {
    "85354-9" ->
      h.td(fixed_time_column_attrs("p-2 border border-slate-700 align-top"), [
        fixed_time_column_inner([
          h.div(
            [
              a.class("grid gap-1 items-center h-full"),
              a.attribute(
                "style",
                "grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);",
              ),
            ],
            [
              number_input(f, "systolic"),
              h.span([], [h.text("/")]),
              number_input(f, "diastolic"),
            ],
          ),
        ]),
      ])
    _ ->
      h.td(fixed_time_column_attrs("p-2 border border-slate-700 align-top"), [
        fixed_time_column_inner([number_input(f, field_name)]),
      ])
  }
}

fn number_input(f: Form(a), name: String) -> Element(msg) {
  h.input([
    a.class("bg-slate-800 border border-slate-700 rounded w-full"),
    a.attribute(
      "style",
      "display: block; width: 100%; max-width: 100%; min-width: 0; height: 2rem; box-sizing: border-box;",
    ),
    a.name(name),
    a.type_("number"),
    a.step("any"),
    a.value(form.field_value(f, name)),
  ])
}
