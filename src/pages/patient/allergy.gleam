import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import terminology/substancecodes
import utils
import utils2

pub type CodingOption {
  CodingOption(code: String, display: String, system: String)
}

pub fn server_created(
  model: Model,
  allergy: r4us.Allergyintolerance,
) -> #(Model, Effect(a)) {
  echo "created"
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_allergies = [allergy, ..data.patient_allergies]
          mm.PatientLoadFound(mm.PatientData(..data, patient_allergies:))
        }
        _ -> patient
      }
      #(
        Model(..model, route: mm.RoutePatient(id:, page:, patient: new_pat)),
        effect.none(),
      )
    }
  }
}

pub fn server_updated(
  model: Model,
  updated_allergy: r4us.Allergyintolerance,
) -> #(Model, Effect(a)) {
  echo "updated"
  echo updated_allergy
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_allergies =
            list.fold(
              from: [],
              over: data.patient_allergies,
              with: fn(acc, old_allergy) {
                let allergy_is_now = case old_allergy.id == updated_allergy.id {
                  True -> updated_allergy
                  False -> old_allergy
                }
                [allergy_is_now, ..acc]
              },
            )
            |> list.reverse
          mm.PatientLoadFound(mm.PatientData(..data, patient_allergies:))
        }
        _ -> patient
      }
      #(
        Model(..model, route: mm.RoutePatient(id:, page:, patient: new_pat)),
        effect.none(),
      )
    }
  }
}

pub fn edit(model: Model, edit_allergy_id: String) {
  echo "hi " <> edit_allergy_id
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id: pat_id, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          case
            data.patient_allergies
            |> list.find(fn(allergy) { allergy.id == Some(edit_allergy_id) })
          {
            Error(_) -> #(model, effect.none())
            Ok(allergy) -> {
              let allergy_form =
                allergy_schema(allergy.patient, Some(allergy))
                |> form.new
                |> form.add_string(
                  "note",
                  utils.annotation_first_text(allergy.note),
                )
                |> form.add_string("criticality", case allergy.criticality {
                  None -> ""
                  Some(c) ->
                    r4us_valuesets.allergyintolerancecriticality_to_string(c)
                })
                |> form.add_string("category", case allergy.category {
                  [] -> ""
                  [c, ..] ->
                    r4us_valuesets.allergyintolerancecategory_to_string(c)
                })
                |> form.add_string("code", case allergy.code {
                  None -> ""
                  Some(cc) ->
                    case cc.coding {
                      [first, ..] -> option.unwrap(first.code, "")
                      [] -> ""
                    }
                })
                |> form.add_string("recorded_date", case allergy.recorded_date {
                  None -> ""
                  Some(rd) -> rd
                })
              let form_existing_allergy =
                allergy_form
                |> Some
                |> mm.PatientAllergies
              let route =
                mm.RoutePatient(
                  id: pat_id,
                  patient:,
                  page: form_existing_allergy,
                )
              let model = Model(..model, route:)
              #(model, effect.none())
            }
          }
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn submit(model: Model, form_allergy: r4us.Allergyintolerance) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let allergy_with_patient =
            r4us.Allergyintolerance(
              ..form_allergy,
              patient: data.patient
                |> utils.patient_to_reference,
            )
          // if the form allergy has no id, user adding a new one
          // if it has id, update the existing allergy on server
          let effect = case allergy_with_patient.id {
            None ->
              r4us_rsvp.allergyintolerance_create(
                allergy_with_patient,
                model.client,
                mm.ServerCreatedAllergy,
              )
            Some(_) ->
              r4us_rsvp.allergyintolerance_update(
                allergy_with_patient,
                model.client,
                mm.ServerUpdatedAllergy,
              )
              |> result.unwrap(effect.none())
            // allergyintolerance_update errors if allergy to update has no id,
            // but we just checked it has id, so that should never happen
          }
          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_errors(model: Model, err: Form(r4us.Allergyintolerance)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientAllergies(Some(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

pub fn allergy_schema(
  patient_ref: r4us.Reference,
  existing_allergy: Option(r4us.Allergyintolerance),
) {
  use note_text <- form.field("note", form.parse_string)
  let note = case note_text {
    "" -> []
    _ -> [r4us.annotation_new(note_text)]
  }
  use criticality_str <- form.field("criticality", form.parse_string)
  let criticality = case
    r4us_valuesets.allergyintolerancecriticality_from_string(criticality_str)
  {
    Ok(c) -> Some(c)
    Error(_) -> None
  }
  use category_str <- form.field("category", form.parse_string)
  let category = case
    r4us_valuesets.allergyintolerancecategory_from_string(category_str)
  {
    Ok(c) -> [c]
    Error(_) -> []
  }
  use code_str <- form.field("code", form.parse_string)
  let code = case
    list.find(substancecodes.substance_codes, fn(entry) { entry.0 == code_str })
  {
    Ok(#(code_val, display)) ->
      Some(
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
      )
    Error(_) -> None
  }
  use recorded_date <- form.field(
    "recorded_date",
    form.parse_optional(form.parse_string),
  )

  let update_allergy = case existing_allergy {
    Some(a) -> a
    None -> r4us.allergyintolerance_new(patient_ref)
  }

  form.success(
    r4us.Allergyintolerance(
      ..update_allergy,
      note:,
      criticality:,
      category:,
      code:,
      recorded_date:,
    ),
  )
}

pub fn view(
  pat: mm.PatientData,
  allergy_form: Option(Form(r4us.Allergyintolerance)),
) {
  let allergy_form = case allergy_form {
    None ->
      form.new(allergy_schema(utils.patient_to_reference(pat.patient), None))
    Some(f) -> f
  }
  let head =
    h.tr(
      [],
      utils.th_list(["allergy", "criticality", "notes", "date_recorded"]),
    )
  let rows =
    list.map(pat.patient_allergies, fn(allergy) {
      case allergy.id {
        None -> element.none()
        Some(allergy_id) ->
          h.tr([], [
            h.td([], [
              case allergy.code {
                None -> element.none()
                Some(cc) ->
                  h.p([], [h.text(utils.codeableconcept_to_string(cc))])
              },
            ]),
            h.td([], [
              case allergy.criticality {
                None -> element.none()
                Some(crit) ->
                  h.p([], [
                    h.text(
                      r4us_valuesets.allergyintolerancecriticality_to_string(
                        crit,
                      ),
                    ),
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
            h.td([], [
              h.button(
                [event.on_click(mm.UserClickedAllergyRowEdit(allergy_id))],
                [
                  h.text("edit"),
                ],
              ),
            ]),
          ])
      }
    })
  [
    h.h1([a.class("text-xl font-bold p-4")], [
      h.text("Allergies and Intolerances"),
    ]),
    h.table([a.class("border-separate border-spacing-4 m-4")], [
      h.thead([], [head]),
      h.tbody([], rows),
    ]),
    h.form(
      [
        a.class("flex flex-row flex-wrap gap-2"),
        event.on_submit(fn(values) {
          allergy_form
          |> form.add_values(values)
          |> form.run
          |> mm.UserSubmittedAllergyForm
        }),
      ],
      [
        view_form_coding_select(
          allergy_form,
          name: "code",
          options: list.map(substancecodes.substance_codes, fn(entry) {
            CodingOption(
              code: entry.0,
              display: entry.1,
              system: "http://snomed.info/sct",
            )
          }),
          label: "allergy",
        ),
        view_form_input(allergy_form, is: "text", name: "note", label: "note"),
        view_form_input(
          allergy_form,
          is: "date",
          name: "recorded_date",
          label: "date recorded",
        ),
        view_form_select(
          allergy_form,
          name: "criticality",
          options: list.map(
            [
              r4us_valuesets.AllergyintolerancecriticalityLow,
              r4us_valuesets.AllergyintolerancecriticalityHigh,
              r4us_valuesets.AllergyintolerancecriticalityUnabletoassess,
            ],
            r4us_valuesets.allergyintolerancecriticality_to_string,
          ),
          label: "criticality",
        ),
        view_form_select(
          allergy_form,
          name: "category",
          options: list.map(
            [
              r4us_valuesets.AllergyintolerancecategoryFood,
              r4us_valuesets.AllergyintolerancecategoryMedication,
              r4us_valuesets.AllergyintolerancecategoryEnvironment,
              r4us_valuesets.AllergyintolerancecategoryBiologic,
            ],
            r4us_valuesets.allergyintolerancecategory_to_string,
          ),
          label: "category",
        ),
        h.div([a.class("flex justify-end")], [
          h.button(
            [
              a.class("text-white text-sm font-bold"),
              a.class("px-4 py-2 bg-purple-600 rounded-lg"),
              a.class("hover:bg-purple-800"),
            ],
            [h.text("Save New Allergy/Intolerance")],
          ),
        ]),
      ],
    ),
  ]
}

fn view_form_select(
  form: Form(a),
  name name: String,
  options options: List(String),
  label label: String,
) {
  let errors = form.field_error_messages(form, name)
  let current_value = form.field_value(form, name)

  h.div([], [
    h.label([a.for(name), a.class("text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.select(
      [
        a.class("border border-slate-700 bg-slate-950"),
        case errors {
          [] -> a.class("focus:outline focus:outline-purple-600")
          _ -> a.class("outline outline-red-500")
        },
        a.id(name),
        a.name(name),
      ],
      [
        h.option([a.value(""), a.selected(current_value == "")], "----"),
        ..list.map(options, fn(option) {
          h.option(
            [a.value(option), a.selected(current_value == option)],
            option,
          )
        })
      ],
    ),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

fn view_form_coding_select(
  form: Form(a),
  name name: String,
  options options: List(CodingOption),
  label label: String,
) {
  let errors = form.field_error_messages(form, name)
  let current_value = form.field_value(form, name)

  h.div([], [
    h.label([a.for(name), a.class("text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.select(
      [
        a.class("border border-slate-700 bg-slate-950"),
        case errors {
          [] -> a.class("focus:outline focus:outline-purple-600")
          _ -> a.class("outline outline-red-500")
        },
        a.id(name),
        a.name(name),
      ],
      [
        h.option([a.value(""), a.selected(current_value == "")], "----"),
        ..list.map(options, fn(option) {
          h.option(
            [a.value(option.code), a.selected(current_value == option.code)],
            option.display,
          )
        })
      ],
    ),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

fn view_form_input(
  form: Form(a),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  h.div([], [
    h.label([a.for(name), a.class("text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.input([
      a.type_(type_),
      a.class("border border-slate-700 bg-slate-950"),
      case errors {
        [] -> a.class("focus:outline focus:outline-purple-600")
        _ -> a.class("outline outline-red-500")
      },
      a.id(name),
      a.name(name),
      a.value(form.field_value(form, name)),
    ]),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}
