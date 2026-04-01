import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre
import lustre/attribute.{type Attribute} as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/svg
import lustre/event
import model_msgs.{type Model, type Msg, Model} as mm
import pages/general/registerpatient
import utils
import utils2

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
      #(
        Model(..model, route: mm.RoutePatient(id:, page:, patient: new_pat)),
        effect.none(),
      )
    }
  }
}

pub fn type_note(model: Model, input, on_id) {
  utils2.if_pat_data_update_patient(model, fn(data) {
    case on_id {
      None -> {
        let new_note = case data.patient_allergy_new.note {
          [] -> [r4us.annotation_new(input)]
          [note] -> [r4us.Annotation(..note, text: input)]
          [note, ..rest] -> [r4us.Annotation(..note, text: input), ..rest]
        }
        let new_allergy =
          r4us.Allergyintolerance(..data.patient_allergy_new, note: new_note)
        mm.PatientData(..data, patient_allergy_new: new_allergy)
      }
      Some(_) -> {
        let on_allergy =
          list.find(data.patient_allergies, fn(allergy) { allergy.id == on_id })
        case on_allergy {
          // strange case if existing allergy has no id to identify it in list
          Error(_) -> data
          Ok(on_allergy) -> {
            let allergy_rest =
              list.filter(data.patient_allergies, fn(allergy) {
                allergy.id != on_id
              })
            let new_note = case on_allergy.note {
              [] -> [r4us.annotation_new(input)]
              [note] -> [r4us.Annotation(..note, text: input)]
              [note, ..note_rest] -> [
                r4us.Annotation(..note, text: input),
                ..note_rest
              ]
            }
            let new_allergy = [
              r4us.Allergyintolerance(..on_allergy, note: new_note),
              ..allergy_rest
            ]
            mm.PatientData(..data, patient_allergies: new_allergy)
          }
        }
      }
    }
  })
}

pub fn create(model: Model) {
  case model.route {
    mm.RouteNoId(page:) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let effect =
            r4us_rsvp.allergyintolerance_create(
              data.patient_allergy_new,
              model.client,
              mm.ServerCreatedAllergy,
            )
          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn view(pat: mm.PatientData) {
  let head =
    h.tr(
      [],
      utils.th_list(["allergy", "criticality", "notes", "date_recorded"]),
    )
  let rows =
    list.map(pat.patient_allergies, fn(allergy) {
      h.tr([], [
        h.td([], [
          case allergy.code {
            None -> element.none()
            Some(cc) -> h.p([], [h.text(utils.codeableconcept_to_string(cc))])
          },
        ]),
        h.td([], [
          case allergy.criticality {
            None -> element.none()
            Some(crit) ->
              h.p([], [
                h.text(r4us_valuesets.allergyintolerancecriticality_to_string(
                  crit,
                )),
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
      ])
    })
  [
    h.h1([a.class("text-xl font-bold p-4")], [
      h.text("Allergies and Intolerances"),
    ]),
    h.table([a.class("border-separate border-spacing-4 m-4")], [
      h.thead([], [head]),
      h.tbody([], rows),
    ]),
    h.div([a.class("flex flex-row gap-2")], [
      h.p([], [h.text("inputs")]),
      h.label([a.for("new-allergy-note")], [h.text("note:")]),
      h.input([
        a.class("border border-slate-700 bg-slate-950"),
        a.id("new-allergy-note"),
        event.on_input(fn(input) {
          mm.UserTypedAllergyintoleranceNote(on_id: None, input:)
        }),
        a.value(case pat.patient_allergy_new.note {
          [] -> ""
          [first, ..] -> first.text
        }),
      ]),
      h.input([a.class("border border-slate-700 bg-slate-950")]),
      h.input([a.class("border border-slate-700 bg-slate-950")]),
      h.label([a.for("criticality")], [h.text("criticality:")]),
      h.select(
        [
          a.class("border border-slate-700 bg-slate-950"),
          a.id("criticality"),
          a.name("criticality"),
        ],
        [
          r4us_valuesets.AllergyintolerancecriticalityLow,
          r4us_valuesets.AllergyintolerancecriticalityHigh,
          r4us_valuesets.AllergyintolerancecriticalityUnabletoassess,
        ]
          |> list.map(fn(criticality) {
            let crit_str =
              r4us_valuesets.allergyintolerancecriticality_to_string(
                criticality,
              )
            h.option(
              [
                a.value(crit_str),
              ],
              crit_str,
            )
          }),
      ),
      h.input([a.class("border border-slate-700 bg-slate-950")]),
      h.button([event.on_click(mm.UserClickedCreateAllergy)], [
        h.text("Save New Allergy/Intolerance"),
      ]),
    ]),
  ]
}
