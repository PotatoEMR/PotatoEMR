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
import terminology/substancecodes
import utils

pub fn update(msg, model) {
  case msg {
    mm.ServerCreatedAllergy(Ok(alrgy), _) -> server_created(model, alrgy)
    mm.ServerCreatedAllergy(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerUpdatedAllergy(Ok(alrgy), _) -> server_updated(model, alrgy)
    mm.ServerUpdatedAllergy(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.ServerDeletedAllergy(Ok(_)) -> #(model, effect.none())
    mm.ServerDeletedAllergy(Error(_)) -> #(model, effect.none())
    mm.UserClickedCreateAllergy -> edit(model, None)
    mm.UserClickedEditAllergy(id) -> edit(model, Some(id))
    mm.UserClickedDeleteAllergy(id) -> delete(model, id)
    mm.UserClickedCloseAllergyForm -> close_form(model)
    mm.UserSubmittedAllergyForm(Ok(new_allergy)) -> submit(model, new_allergy)
    mm.UserSubmittedAllergyForm(Error(err)) -> form_errors(model, err)
  }
}

pub fn server_created(
  model: Model,
  allergy: r4us.Allergyintolerance,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) -> {
          let patient_allergies = list.append(data.patient_allergies, [allergy])
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
    mm.RoutePatient(id:, page: _, patient:) -> {
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
    mm.RoutePatient(id: pat_id, patient:, page: _) ->
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
                  allergy_form(allergy, edit_allergy_id)
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
  #(Model(..model, route:), effect.none())
}

fn allergy_form(allergy: r4us.Allergyintolerance, allergy_id: String) {
  allergy_schema(allergy)
  |> form.new
  |> form.add_string("note", utils.annotation_first_text(allergy.note))
  |> form.add_string("type_", case allergy.type_ {
    None -> ""
    Some(t) -> r4us_valuesets.allergyintolerancetype_to_string(t)
  })
  |> form.add_string("criticality", case allergy.criticality {
    None -> ""
    Some(c) -> r4us_valuesets.allergyintolerancecriticality_to_string(c)
  })
  |> form.add_string("category", case allergy.category {
    [] -> ""
    [c, ..] -> r4us_valuesets.allergyintolerancecategory_to_string(c)
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
    Some(primitive_types.DateTime(date:, ..)) ->
      date |> primitive_types.date_to_string
  })
  // id is in form probably just so view knows if editing or creating
  |> form.add_string("id", allergy_id)
}

pub fn server_error(
  model: Model,
  submitted_form: Form(r4us.Allergyintolerance),
  err: r4us_rsvp.Err,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let allergy_form =
        submitted_form
        |> form.add_error(
          "code",
          form.CustomError("Server error: " <> utils.err_to_string(err)),
        )
        |> mm.FormStateSome
        |> mm.PatientAllergies
      let route = mm.RoutePatient(id:, patient:, page: allergy_form)
      #(Model(..model, route:), effect.none())
    }
  }
}

pub fn submit(model: Model, form_allergy: r4us.Allergyintolerance) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let submitted_form = case page {
            mm.PatientAllergies(mm.FormStateSome(f)) -> f
            _ -> form.new(allergy_schema(form_allergy))
          }
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
                fn(result) { mm.ServerCreatedAllergy(result, submitted_form) },
              )
            Some(_) ->
              r4us_rsvp.allergyintolerance_update(
                allergy_with_patient,
                model.client,
                fn(result) { mm.ServerUpdatedAllergy(result, submitted_form) },
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
  Model(..model, route:)
}

pub fn delete(model: Model, allergy_id: String) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          case
            data.patient_allergies
            |> list.find(fn(a) { a.id == Some(allergy_id) })
          {
            Error(_) -> #(model, effect.none())
            Ok(allergy) -> {
              let eff =
                r4us_rsvp.allergyintolerance_delete(
                  allergy,
                  model.client,
                  mm.ServerDeletedAllergy,
                )
                |> result.unwrap(effect.none())
              let patient_allergies =
                data.patient_allergies
                |> list.filter(fn(a) { a.id != Some(allergy_id) })
              let new_pat =
                mm.PatientLoadFound(mm.PatientData(..data, patient_allergies:))
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

pub fn form_errors(model: Model, err: Form(r4us.Allergyintolerance)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> #(
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
  use form_recorded_date <- form.field(
    "recorded_date",
    form.parse_optional(form.parse_string),
  )
  let recorded_date = case form_recorded_date {
    Some(rd) ->
      case primitive_types.parse_datetime(rd) {
        Ok(rd) -> Some(rd)
        Error(_) -> None
      }
    None -> None
  }
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
      utils.th_list([
        "allergy",
        "type",
        "criticality",
        "notes",
        "date recorded",
        "",
      ]),
    )
  let rows =
    list.map(pat.patient_allergies, fn(allergy) {
      case allergy.id {
        None -> element.none()
        Some(allergy_id) ->
          h.tr([a.class("border-b border-slate-700")], [
            h.td([a.class("p-2")], [
              case allergy.code {
                None -> element.none()
                Some(cc) ->
                  h.p([], [h.text(utils.codeableconcept_to_string(cc))])
              },
            ]),
            h.td([a.class("p-2")], [
              case allergy.type_ {
                None -> element.none()
                Some(t) ->
                  h.p([], [
                    h.text(r4us_valuesets.allergyintolerancetype_to_string(t)),
                  ])
              },
            ]),
            h.td([a.class("p-2")], [
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
            h.td([a.class("p-2 max-w-xs truncate")], [
              h.text(utils.annotation_first_text(allergy.note)),
            ]),
            h.td([a.class("p-2")], [
              case allergy.recorded_date {
                None -> element.none()
                Some(rd) -> h.text(rd |> primitive_types.datetime_to_string)
              },
            ]),
            h.td([a.class("p-2 flex gap-2")], [
              btn("Edit", on_click: mm.UserClickedEditAllergy(allergy_id)),
              btn("Delete", on_click: mm.UserClickedDeleteAllergy(allergy_id)),
            ]),
          ])
      }
    })
  [
    h.div([a.class("p-4 max-w-4xl")], [
      h.div([a.class("flex items-center gap-4 mb-4")], [
        h.h1([a.class("text-xl font-bold")], [
          h.text("Allergies and Intolerances"),
        ]),
        btn(
          "Create New Allergy/Intolerance",
          on_click: mm.UserClickedCreateAllergy,
        ),
      ]),
      h.table([a.class("border-collapse border border-slate-700")], [
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
                  view_form_textarea(allergy_form, name: "note", label: "note"),
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
                    btn_cancel(
                      "Cancel",
                      on_click: mm.UserClickedCloseAllergyForm,
                    ),
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
