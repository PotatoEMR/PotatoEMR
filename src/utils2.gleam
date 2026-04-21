import gleam/dynamic
import lustre/effect.{type Effect}
import model_msgs.{type Model, Model} as mm

pub fn update_patient(
  model: Model,
  update_pat: fn(mm.PatientLoad) -> mm.PatientLoad,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      let new_pat = update_pat(patient)
      #(
        Model(..model, route: mm.RoutePatient(id:, page:, patient: new_pat)),
        effect.none(),
      )
    }
  }
}

// if model doesnt have patient when trying to update patient data (weird?), don't do anything
// could maybe use the other update_patient fn but want to be able to send effect
pub fn if_pat_data_update_patient(
  model: Model,
  update_pat: fn(mm.PatientData) -> mm.PatientData,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page:, patient:) -> {
      case patient {
        mm.PatientLoadFound(data:) -> {
          let newpatient = mm.PatientLoadFound(update_pat(data))
          let model =
            Model(
              ..model,
              route: mm.RoutePatient(id:, page:, patient: newpatient),
            )
          #(model, effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
  }
}

@external(javascript, "./potatoemr_ffi.mjs", "read_file_from_event")
pub fn read_file_from_event(
  event: dynamic.Dynamic,
  callback: fn(String) -> Nil,
) -> Nil

@external(javascript, "./potatoemr_ffi.mjs", "setup_body_dropzone")
pub fn setup_body_dropzone(
  on_drag: fn(Bool) -> Nil,
  on_drop_file: fn(String) -> Nil,
) -> Nil
