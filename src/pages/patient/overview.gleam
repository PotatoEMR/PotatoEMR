import fhir/primitive_types
import fhir/r4us
import fhir/r4us_valuesets
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import model_msgs as mm
import pages/patient/vitals
import utils
import colors

pub fn view(data: mm.PatientData) -> List(Element(msg)) {
  let id = case data.patient.id {
    Some(id) -> id
    None -> ""
  }
  [
    h.div(
      [a.class("p-4 columns-1 md:columns-2 xl:columns-3 gap-4")],
      [
        demographics_box(id, data),
        allergies_box(id, data),
        encounters_box(id, data),
        immunizations_box(id, data),
        medications_box(id, data),
        orders_box(id, data),
        vitals_box(id, data),
      ],
    ),
  ]
}

fn box(
  id: String,
  page: mm.RoutePatientPage,
  label: String,
  bar_color: String,
  count: option.Option(Int),
  body: List(Element(msg)),
) -> Element(msg) {
  h.a(
    [
      mm.href(mm.RoutePatient(id, mm.PatientLoadStillLoading, page)),
      a.class(
        "break-inside-avoid mb-4 block rounded-lg overflow-hidden " <> colors.bg_base <> " border-l-4 "
        <> bar_color
        <> " " <> colors.hover_bg_surface_0 <> " transition-colors",
      ),
    ],
    [
      h.div([a.class("p-3 flex flex-col gap-2")], [
        h.div(
          [
            a.class(
              "flex items-baseline justify-between border-b " <> colors.border_surface_0 <> " pb-1",
            ),
          ],
          [
            h.p(
              [
                a.class(
                  "text-sm font-semibold " <> colors.text <> " uppercase tracking-wide",
                ),
              ],
              [h.text(label)],
            ),
            case count {
              None -> element.none()
              Some(n) ->
                h.p([a.class("text-xs " <> colors.subtext_1)], [
                  h.text(int.to_string(n)),
                ])
            },
          ],
        ),
        h.div([a.class("text-sm " <> colors.text <> " flex flex-col gap-1")], body),
      ]),
    ],
  )
}

fn empty_line(text: String) -> Element(msg) {
  h.p([a.class(colors.subtext_1 <> " italic")], [h.text(text)])
}

fn demographics_box(id: String, data: mm.PatientData) -> Element(msg) {
  let name = utils.humannames_to_single_name_string(data.patient.name)
  let gender = case data.patient.gender {
    None -> "—"
    Some(g) -> r4us_valuesets.administrativegender_to_string(g)
  }
  let dob = case data.patient.birth_date {
    None -> "—"
    Some(d) -> primitive_types.date_to_string(d)
  }
  let identifier = case data.patient.identifier {
    [] -> ""
    [first, ..] -> option.unwrap(first.value, "")
  }
  box(
    id,
    mm.PatientDemographics(mm.FormStateNone),
    "Demographics",
    colors.border_blue,
    None,
    [
      h.p([a.class("font-bold text-base")], [h.text(name)]),
      h.p([a.class(colors.subtext_1)], [h.text("Gender: " <> gender)]),
      h.p([a.class(colors.subtext_1)], [h.text("DOB: " <> dob)]),
      case identifier {
        "" -> element.none()
        s -> h.p([a.class(colors.subtext_1)], [h.text("ID: " <> s)])
      },
    ],
  )
}

fn allergies_box(id: String, data: mm.PatientData) -> Element(msg) {
  let allergies = data.patient_allergies
  let body = case allergies {
    [] -> [empty_line("No allergies recorded")]
    _ ->
      list.take(allergies, 5)
      |> list.map(fn(al) {
        let name = case al.code {
          None -> "unspecified"
          Some(cc) -> utils.codeableconcept_to_string(cc)
        }
        let crit = case al.criticality {
          None -> ""
          Some(c) ->
            " · "
            <> r4us_valuesets.allergyintolerancecriticality_to_string(c)
        }
        h.p([], [h.text(name <> crit)])
      })
  }
  box(
    id,
    mm.PatientAllergies(mm.FormStateNone),
    "Allergies",
    colors.border_flamingo,
    None,
    body,
  )
}

fn encounters_box(id: String, data: mm.PatientData) -> Element(msg) {
  let encounters = data.patient_encounters
  let body = case encounters {
    [] -> [empty_line("No encounters")]
    _ ->
      list.take(encounters, 5)
      |> list.map(fn(enc) {
        let date = case enc.period {
          Some(p) ->
            case p.start {
              Some(d) -> primitive_types.datetime_to_string(d)
              None -> ""
            }
          None -> ""
        }
        let status = r4us_valuesets.encounterstatus_to_string(enc.status)
        let text = case date {
          "" -> status
          _ -> date <> " · " <> status
        }
        h.p([], [h.text(text)])
      })
  }
  box(
    id,
    mm.PatientEncounters(mm.FormStateNone),
    "Encounters",
    colors.border_mauve,
    None,
    body,
  )
}

fn immunizations_box(id: String, data: mm.PatientData) -> Element(msg) {
  let imms = data.patient_immunizations
  let body = case imms {
    [] -> [empty_line("No immunizations")]
    _ ->
      list.take(imms, 5)
      |> list.map(fn(imm) {
        let name = utils.codeableconcept_to_string(imm.vaccine_code)
        let when_ = case imm.occurrence {
          r4us.ImmunizationOccurrenceDatetime(d) ->
            primitive_types.datetime_to_string(d)
          r4us.ImmunizationOccurrenceString(s) -> s
        }
        let text = case when_ {
          "" -> name
          _ -> name <> " · " <> when_
        }
        h.p([], [h.text(text)])
      })
  }
  box(
    id,
    mm.PatientImmunizations(mm.FormStateNone),
    "Immunizations",
    colors.border_green,
    None,
    body,
  )
}

fn medications_box(id: String, data: mm.PatientData) -> Element(msg) {
  let meds = data.patient_medication_statements
  let body = case meds {
    [] -> [empty_line("No medications")]
    _ ->
      list.take(meds, 5)
      |> list.map(fn(ms) {
        let name = case ms.medication {
          r4us.MedicationstatementMedicationCodeableconcept(cc) ->
            utils.codeableconcept_to_string(cc)
          r4us.MedicationstatementMedicationReference(ref) ->
            option.unwrap(ref.display, "")
        }
        let status =
          r4us_valuesets.medicationstatementstatus_to_string(ms.status)
        h.p([], [h.text(name <> " · " <> status)])
      })
  }
  box(
    id,
    mm.PatientMedications(mm.FormStateNone),
    "Medications",
    colors.border_peach,
    Some(list.length(meds)),
    body,
  )
}

fn orders_box(id: String, data: mm.PatientData) -> Element(msg) {
  let orders = data.patient_medication_requests
  let body = case orders {
    [] -> [empty_line("No orders")]
    _ ->
      list.take(orders, 5)
      |> list.map(fn(mr) {
        let name = case mr.medication {
          r4us.MedicationrequestMedicationCodeableconcept(cc) ->
            utils.codeableconcept_to_string(cc)
          r4us.MedicationrequestMedicationReference(ref) ->
            option.unwrap(ref.display, "")
        }
        let status =
          r4us_valuesets.medicationrequeststatus_to_string(mr.status)
        h.p([], [h.text(name <> " · " <> status)])
      })
  }
  box(
    id,
    mm.PatientOrders(mm.FormStateNone),
    "Orders",
    colors.border_sky,
    Some(list.length(orders)),
    body,
  )
}

fn latest_per_vital(
  observations: List(r4us.Observation),
) -> List(#(String, String, String)) {
  let sorted =
    observations
    |> list.filter(vitals.is_vital_signs)
    |> list.filter(fn(o) { vitals.obs_code(o) != "85353-1" })
    |> list.sort(fn(a, b) {
      string.compare(vitals.obs_time(b), vitals.obs_time(a))
    })
  list.filter_map(vitals.vital_columns, fn(col) {
    let #(code, label, _) = col
    case list.find(sorted, fn(o) { vitals.obs_code(o) == code }) {
      Error(_) -> Error(Nil)
      Ok(obs) ->
        case vitals.cell_value(obs, code) {
          "" -> Error(Nil)
          v -> Ok(#(label, v, vitals.obs_time(obs)))
        }
    }
  })
}

fn vitals_box(id: String, data: mm.PatientData) -> Element(msg) {
  let latest = latest_per_vital(data.patient_observations)
  let body = case latest {
    [] -> [empty_line("No vitals recorded")]
    _ -> [
      h.table([], [
        h.tbody(
          [],
          list.map(latest, fn(row) {
            h.tr([], [
              h.td([a.class(colors.subtext_1 <> " pr-3 py-0.5")], [h.text(row.0)]),
              h.td([a.class("pr-3 py-0.5")], [h.text(row.1)]),
              h.td([a.class(colors.subtext_1 <> " text-xs py-0.5")], [
                h.text(row.2),
              ]),
            ])
          }),
        ),
      ]),
    ]
  }
  box(
    id,
    mm.PatientVitals(mm.FormStateNone),
    "Vitals",
    colors.border_pink,
    None,
    body,
  )
}
