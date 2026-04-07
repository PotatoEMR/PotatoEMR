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
      let model =
        model
        |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone)
      #(model, effect.none())
    }
  }
}

pub fn server_updated(
  model: Model,
  updated_allergy: r4us.Allergyintolerance,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_allergies =
            data.patient_allergies
            |> list.map(fn(old_allergy) {
              case old_allergy.id == updated_allergy.id {
                True -> updated_allergy
                False -> old_allergy
              }
            })
          mm.PatientLoadFound(mm.PatientData(..data, patient_allergies:))
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

pub fn edit(model: Model, edit_allergy_id: Option(String)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id: pat_id, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          // click create new allergy -> form for new allergy, edit_allergy_id None
          // click edit on allergy row -> form for existing allergy, with its id
          case edit_allergy_id {
            Some(edit_allergy_id) -> {
              case
                data.patient_allergies
                |> list.find(fn(allergy) { allergy.id == Some(edit_allergy_id) })
              {
                Error(_) -> #(model, effect.none())
                Ok(allergy) -> {
                  allergy_schema(allergy)
                  |> form.new
                  |> form.add_string(
                    "note",
                    utils.annotation_first_text(allergy.note),
                  )
                  |> form.add_string("type_", case allergy.type_ {
                    None -> ""
                    Some(t) ->
                      r4us_valuesets.allergyintolerancetype_to_string(t)
                  })
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
                  |> form.add_string(
                    "recorded_date",
                    case allergy.recorded_date {
                      None -> ""
                      Some(rd) -> rd
                    },
                  )
                  // id is in form probably just so view knows if editing or creating
                  |> form.add_string("id", edit_allergy_id)
                  |> form_to_model(model, pat_id, patient)
                }
              }
            }
            None -> {
              data.patient
              |> utils.patient_to_reference
              |> r4us.allergyintolerance_new
              |> allergy_schema
              |> form.new
              |> form_to_model(model, pat_id, patient)
            }
          }
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_to_model(allergy_form, model, pat_id, patient) {
  let allergy_form =
    allergy_form
    |> mm.FormStateSome
    |> mm.PatientAllergies
  let route = mm.RoutePatient(id: pat_id, patient:, page: allergy_form)
  let model = Model(..model, route:)
  #(model, effect.none())
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
  let allergy_form = mm.PatientAllergies(formstate)
  let route = mm.RoutePatient(id:, patient:, page: allergy_form)
  let model = Model(..model, route:)
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

pub fn form_errors(model: Model, err: Form(r4us.Allergyintolerance)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientAllergies(mm.FormStateSome(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

pub fn allergy_schema(allergy: r4us.Allergyintolerance) {
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
  use type_str <- form.field("type_", form.parse_string)
  let type_ = case r4us_valuesets.allergyintolerancetype_from_string(type_str) {
    Ok(t) -> Some(t)
    Error(_) -> None
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
  form.success(
    r4us.Allergyintolerance(
      ..allergy,
      note:,
      type_:,
      criticality:,
      category:,
      code:,
      recorded_date:,
    ),
  )
}

pub fn view(
  pat: mm.PatientData,
  allergy_form: mm.FormState(r4us.Allergyintolerance),
) {
  let head =
    h.tr(
      [],
      utils.th_list(["allergy", "type", "criticality", "notes", "date_recorded"]),
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
              case allergy.type_ {
                None -> element.none()
                Some(t) ->
                  h.p([], [
                    h.text(r4us_valuesets.allergyintolerancetype_to_string(t)),
                  ])
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
              btn("Edit", on_click: mm.UserClickedEditAllergy(allergy_id)),
            ]),
          ])
      }
    })
  [
    h.div([a.class("p-4 max-w-4xl")], [
      h.div([a.class("flex items-center gap-4")], [
        h.h1([a.class("text-xl font-bold")], [
          h.text("Allergies and Intolerances"),
        ]),
        btn("Create New Allergy/Intolerance", on_click: mm.UserClickedCreateAllergy),
      ]),
      h.table([a.class("border-separate border-spacing-4")], [
      h.thead([], [head]),
      h.tbody([], rows),
    ]),
    case allergy_form {
      mm.FormStateNone -> element.none()
      mm.FormStateLoading -> h.p([], [h.text("loading...")])
      mm.FormStateSome(allergy_form) -> {
        let legend_text = case form.field_value(allergy_form, "id") {
          "" -> "Create Allergy/Intolerance"
          _ -> {
            let code = form.field_value(allergy_form, "code")
            let display =
              substancecodes.substance_codes
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
              allergy_form
              |> form.add_values(values)
              |> form.run
              |> mm.UserSubmittedAllergyForm
            }),
          ],
          [
            h.fieldset(
              [a.class("border border-slate-600 rounded-lg p-4 flex flex-row flex-wrap gap-4")],
              [
                h.legend([a.class("px-2 text-sm font-bold text-slate-200")], [
                  h.text(legend_text),
                ]),
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
                view_form_input(
                  allergy_form,
                  is: "text",
                  name: "note",
                  label: "note",
                ),
                view_form_input(
                  allergy_form,
                  is: "date",
                  name: "recorded_date",
                  label: "date recorded",
                ),
                view_form_select(
                  allergy_form,
                  name: "type_",
                  options: list.map(
                    [
                      r4us_valuesets.AllergyintolerancetypeAllergy,
                      r4us_valuesets.AllergyintolerancetypeIntolerance,
                    ],
                    r4us_valuesets.allergyintolerancetype_to_string,
                  ),
                  label: "type",
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
                h.div([a.class("w-full flex justify-end gap-2")], [
                  btn("Cancel", on_click: mm.UserClickedCloseAllergyForm),
                  btn_nomsg("Save Allergy/Intolerance"),
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

fn btn_attrs() {
  [
    a.class("text-sm font-bold px-4 py-2 rounded-lg"),
    a.class("border border-slate-600 text-slate-200 bg-slate-800"),
    a.class("hover:bg-slate-700"),
  ]
}

fn btn(label: String, on_click msg: msg) -> Element(msg) {
  h.button([event.on_click(msg), ..btn_attrs()], [h.text(label)])
}

fn btn_nomsg(label: String) -> Element(msg) {
  h.button(btn_attrs(), [h.text(label)])
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
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
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
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
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
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
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
