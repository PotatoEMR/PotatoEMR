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
    mm.UserClickedCloseVitalsForm -> set_form_state(model, mm.FormStateNone)
    mm.UserSubmittedVitalsForm(Ok(observations)) -> submit(model, observations)
    mm.UserSubmittedVitalsForm(Error(err)) ->
      set_form_state(model, mm.FormStateSome(err))
    mm.ServerReturnedVitalsBundle(Ok(bundle)) -> bundle_returned(model, bundle)
    mm.ServerReturnedVitalsBundle(Error(_)) ->
      set_form_state(model, mm.FormStateNone)
  }
}

fn open_form(model: Model) {
  case patient_ref(model) {
    None -> #(model, effect.none())
    Some(ref) -> {
      let f = vitals_schema(ref) |> form.new
      set_form_state(model, mm.FormStateSome(f))
    }
  }
}

fn patient_ref(model: Model) -> Option(r4us.Reference) {
  case model.route {
    mm.RoutePatient(
      patient: mm.PatientLoadFound(data:),
      id: _,
      page: _,
    ) -> Some(utils.patient_to_reference(data.patient))
    _ -> None
  }
}

fn set_form_state(
  model: Model,
  formstate: mm.FormState(List(r4us.Observation)),
) {
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
      let reqs =
        list.map(observations, fn(obs) {
          r4us_sansio.observation_create_req(obs, model.client)
        })
      let eff =
        r4us_rsvp.batch(
          reqs,
          r4us_sansio.Transaction,
          model.client,
          mm.ServerReturnedVitalsBundle,
        )
      let #(model, _) = set_form_state(model, mm.FormStateLoading)
      #(model, eff)
    }
  }
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
      let patient_observations =
        list.append(data.patient_observations, returned_obs)
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
  r4us.Codeableconcept(
    ..r4us.codeableconcept_new(),
    coding: [
      utils.coding(
        code: "vital-signs",
        system: vital_signs_category_system,
        display: "Vital Signs",
      ),
    ],
  )
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
  patient_ref: r4us.Reference,
  effective: Option(r4us.ObservationEffective),
  code: String,
  display: String,
  unit: String,
  value: Float,
) -> r4us.Observation {
  r4us.Observation(
    ..r4us.observation_new(
      code: loinc_cc(code, display),
      status: r4us_valuesets.ObservationstatusFinal,
    ),
    category: [vital_category()],
    subject: Some(patient_ref),
    effective:,
    value: Some(r4us.ObservationValueQuantity(ucum_qty(value, unit))),
  )
}

fn bp_component(code: String, display: String, value: Float) {
  r4us.ObservationComponent(
    ..r4us.observation_component_new(code: loinc_cc(code, display)),
    value: Some(r4us.ObservationComponentValueQuantity(ucum_qty(value, "mm[Hg]"))),
  )
}

fn make_bp_obs(
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
  r4us.Observation(
    ..r4us.observation_new(
      code: loinc_cc("85354-9", "Blood pressure panel with all children optional"),
      status: r4us_valuesets.ObservationstatusFinal,
    ),
    category: [vital_category()],
    subject: Some(patient_ref),
    effective:,
    component: components,
  )
}

fn vitals_schema(patient_ref: r4us.Reference) {
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
  use systolic <- form.field(
    "systolic",
    form.parse_optional(form.parse_float),
  )
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
    #(head_circumference, "9843-4", "Head Occipital-frontal circumference", "cm"),
    #(body_weight, "29463-7", "Body weight", "kg"),
    #(bmi, "39156-5", "Body mass index (BMI) [Ratio]", "kg/m2"),
  ]

  let simple_obs =
    list.filter_map(simple, fn(t) {
      case t.0 {
        Some(v) -> Ok(make_quantity_obs(patient_ref, effective, t.1, t.2, t.3, v))
        None -> Error(Nil)
      }
    })

  let bp_obs = case systolic, diastolic {
    None, None -> []
    _, _ -> [make_bp_obs(patient_ref, effective, systolic, diastolic)]
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

  let time_header_cells = list.map(time_groups, fn(pair) {
    utils.th_bordered(pair.0)
  })
  let form_header_cell = case form_opt {
    Some(f) -> [form_datetime_cell(f)]
    None -> []
  }
  let head =
    h.tr(
      [],
      [utils.th_bordered(""), ..list.append(form_header_cell, time_header_cells)],
    )

  let rows =
    list.map(vital_columns, fn(col) {
      let #(code, label, field_name) = col
      let form_input_cells = case form_opt {
        Some(f) -> [form_value_cell(f, code, field_name)]
        None -> []
      }
      let time_cells =
        list.map(time_groups, fn(pair) {
          let obs_list = pair.1
          let val = case list.find(obs_list, fn(o) { obs_code(o) == code }) {
            Ok(obs) -> cell_value(obs, code)
            Error(_) -> ""
          }
          h.td([a.class("p-2 text-left border border-slate-700")], [h.text(val)])
        })
      h.tr([a.class("border-b border-slate-700")], [
        h.th([a.class("p-2 text-left border border-slate-700")], [h.text(label)]),
        ..list.append(form_input_cells, time_cells)
      ])
    })

  let footer_rows = case form_opt {
    None -> []
    Some(_) -> {
      let empty_time_cells =
        list.map(time_groups, fn(_) {
          h.td([a.class("border border-slate-700")], [])
        })
      [
        h.tr([], [
          h.td([a.class("border border-slate-700")], []),
          h.td([a.class("p-2 border border-slate-700")], [
            h.div([a.class("flex gap-2 justify-end")], [
              btn_cancel("Cancel", on_click: mm.UserClickedCloseVitalsForm),
              btn_nomsg("Save"),
            ]),
          ]),
          ..empty_time_cells
        ]),
      ]
    }
  }

  let is_loading = case vitals_form {
    mm.FormStateLoading -> True
    _ -> False
  }

  let table =
    h.table([a.class("border-collapse border border-slate-700")], [
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
        case form_opt, is_loading {
          None, False ->
            btn(
              "Create New Vital Signs Panel",
              on_click: mm.UserClickedCreateVitals,
            )
          _, True -> h.span([a.class("text-sm")], [h.text("saving...")])
          _, _ -> element.none()
        },
      ]),
      h.div([a.class("overflow-x-auto")], [wrapped]),
    ]),
  ]
}

fn form_datetime_cell(f: Form(a)) -> Element(mm.SubmsgVitals) {
  let name = "effective_datetime"
  let errors = form.field_error_messages(f, name)
  h.th([a.class("p-2 text-left border border-slate-700")], [
    h.input([
      a.class("bg-slate-800 border border-slate-700 rounded p-1 w-full"),
      a.name(name),
      a.type_("datetime-local"),
      a.value(form.field_value(f, name)),
    ]),
    ..list.map(errors, fn(e) {
      h.div([a.class("text-xs text-red-400")], [h.text(e)])
    })
  ])
}

fn form_value_cell(
  f: Form(a),
  code: String,
  field_name: String,
) -> Element(mm.SubmsgVitals) {
  case code {
    "85354-9" ->
      h.td([a.class("p-2 border border-slate-700")], [
        h.div([a.class("flex gap-1 items-center")], [
          number_input(f, "systolic"),
          h.span([], [h.text("/")]),
          number_input(f, "diastolic"),
        ]),
        ..list.append(
          list.map(form.field_error_messages(f, "systolic"), fn(e) {
            h.div([a.class("text-xs text-red-400")], [h.text(e)])
          }),
          list.map(form.field_error_messages(f, "diastolic"), fn(e) {
            h.div([a.class("text-xs text-red-400")], [h.text(e)])
          }),
        )
      ])
    _ ->
      h.td([a.class("p-2 border border-slate-700")], [
        number_input(f, field_name),
        ..list.map(form.field_error_messages(f, field_name), fn(e) {
          h.div([a.class("text-xs text-red-400")], [h.text(e)])
        })
      ])
  }
}

fn number_input(f: Form(a), name: String) -> Element(msg) {
  h.input([
    a.class("bg-slate-800 border border-slate-700 rounded p-1 w-24"),
    a.name(name),
    a.type_("number"),
    a.step("any"),
    a.value(form.field_value(f, name)),
  ])
}
