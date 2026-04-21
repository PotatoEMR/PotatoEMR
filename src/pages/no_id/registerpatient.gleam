import fhir/r4us
import fhir/r4us_rsvp
import formal/form.{type Form}
import gleam/option.{type Option, None, Some}
import lustre/attribute as a
import lustre/effect
import lustre/element/html as h
import model_msgs.{type Model, Model} as mm
import modem
import pages/patient/demographics
import utils

pub fn update(msg, model) {
  case msg {
    mm.UserClickedRegisterPatient(Ok(newpat)) -> create(model, newpat)
    mm.UserClickedRegisterPatient(Error(err)) -> form_errors(model, err)
    mm.UserClickedAddRegisterPatientName(values) -> add_name(model, values)
    mm.UserClickedDeleteRegisterPatientName(values) ->
      delete_name(model, values)
    mm.UserClickedAddRegisterPatientRecordedGender(values) ->
      add_recorded_gender(model, values)
    mm.UserClickedDeleteRegisterPatientRecordedGender(values) ->
      delete_recorded_gender(model, values)
    mm.UserClickedAddRegisterPatientIdentifier(values) ->
      add_identifier(model, values)
    mm.UserClickedDeleteRegisterPatientIdentifier(values) ->
      delete_identifier(model, values)
    mm.ServerReturnedRegisterPatient(Ok(created_pat)) ->
      created(model, created_pat)
    mm.ServerReturnedRegisterPatient(Error(err)) -> create_error(model, err)
  }
}

pub fn create(model: Model, newpat: r4us.Patient) {
  let effect =
    r4us_rsvp.patient_create(
      newpat,
      model.client,
      mm.ServerReturnedRegisterPatient,
    )
  #(model, effect)
}

pub fn form_errors(model: Model, err: Form(r4us.Patient)) {
  set_form(model, err)
}

fn add_name(model: Model, values: List(#(String, String))) {
  update_form(model, values, demographics.form_add_name)
}

fn delete_name(model: Model, values: List(#(String, String))) {
  update_form(model, values, demographics.form_delete_name)
}

fn add_recorded_gender(model: Model, values: List(#(String, String))) {
  update_form(model, values, demographics.form_add_recorded_gender)
}

fn delete_recorded_gender(model: Model, values: List(#(String, String))) {
  update_form(model, values, demographics.form_delete_recorded_gender)
}

fn add_identifier(model: Model, values: List(#(String, String))) {
  update_form(model, values, demographics.form_add_identifier)
}

fn delete_identifier(model: Model, values: List(#(String, String))) {
  update_form(model, values, demographics.form_delete_identifier)
}

fn update_form(
  model: Model,
  values: List(#(String, String)),
  update_fn: fn(Form(r4us.Patient), List(#(String, String))) ->
    Form(r4us.Patient),
) {
  let updated = update_fn(current_form(model), values)
  set_form(model, updated)
}

fn current_form(model: Model) -> Form(r4us.Patient) {
  case model.route {
    mm.RouteNoId(mm.RegisterPatient(Some(newpatient))) -> newpatient
    _ -> default_form()
  }
}

fn default_form() -> Form(r4us.Patient) {
  form.new(demographics.patient_schema(blank_patient()))
}

fn set_form(model: Model, newpatient: Form(r4us.Patient)) {
  case model.route {
    mm.RouteNoId(mm.RegisterPatient(_)) -> #(
      Model(..model, route: mm.RouteNoId(mm.RegisterPatient(Some(newpatient)))),
      effect.none(),
    )
    _ -> #(model, effect.none())
  }
}

pub fn created(model: Model, created_pat: r4us.Patient) {
  case created_pat.id {
    None -> {
      let updated_form =
        current_form(model)
        |> form.add_error(
          demographics.patient_form_server_error_name,
          form.CustomError(
            "Server error: created patient did not include an id",
          ),
        )
      set_form(model, updated_form)
    }
    Some(id) -> {
      let pat_url =
        mm.route_to_urlstring(mm.RoutePatient(
          id,
          mm.PatientLoadStillLoading,
          mm.PatientOverview,
        ))
        |> modem.push(None, None)
      #(model, pat_url)
    }
  }
}

pub fn create_error(model: Model, err: r4us_rsvp.Err) {
  let updated_form =
    current_form(model)
    |> form.add_error(
      demographics.patient_form_server_error_name,
      form.CustomError("Server error: " <> utils.err_to_string(err)),
    )
  set_form(model, updated_form)
}

pub fn view(newpatient: Option(Form(r4us.Patient))) {
  let pat = blank_patient()
  let newpatient = case newpatient {
    Some(newpatient) -> newpatient
    None -> default_form()
  }
  [
    h.div([a.class("p-4 max-w-5xl")], [
      demographics.view_patient_form(
        newpatient,
        pat,
        "Register Patient",
        "Register",
        mm.UserClickedRegisterPatient,
        mm.UserClickedAddRegisterPatientName,
        mm.UserClickedDeleteRegisterPatientName,
        mm.UserClickedAddRegisterPatientRecordedGender,
        mm.UserClickedDeleteRegisterPatientRecordedGender,
        mm.UserClickedAddRegisterPatientIdentifier,
        mm.UserClickedDeleteRegisterPatientIdentifier,
        None,
      ),
    ]),
  ]
}

fn blank_patient() -> r4us.Patient {
  r4us.patient_new()
}
