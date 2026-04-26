import colors
import components.{
  btn, btn_attrs, btn_cancel, btn_nomsg, view_form_input, view_form_input_wide,
  view_form_select,
}
import fhir/primitive_types
import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
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
import terminology/genderidentity
import utils

pub fn update(msg, model) {
  case msg {
    mm.ServerUpdatedPatientDemographics(Ok(pat), _) ->
      server_updated(model, pat)
    mm.ServerUpdatedPatientDemographics(Error(err), submitted_form) ->
      server_error(model, submitted_form, err)
    mm.UserClickedEditDemographics -> edit(model)
    mm.UserClickedCloseDemographicsForm -> close_form(model)
    mm.UserClickedAddDemographicsName(values) -> add_name(model, values)
    mm.UserClickedDeleteDemographicsName(values) -> delete_name(model, values)
    mm.UserClickedAddDemographicsRecordedGender(values) ->
      add_recorded_gender(model, values)
    mm.UserClickedDeleteDemographicsRecordedGender(values) ->
      delete_recorded_gender(model, values)
    mm.UserClickedAddDemographicsIdentifier(values) ->
      add_identifier(model, values)
    mm.UserClickedDeleteDemographicsIdentifier(values) ->
      delete_identifier(model, values)
    mm.UserSubmittedDemographicsForm(Ok(new_pat)) -> submit(model, new_pat)
    mm.UserSubmittedDemographicsForm(Error(err)) -> form_errors(model, err)
  }
}

pub fn server_updated(
  model: Model,
  updated_patient: r4us.Patient,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let new_pat = case patient {
        mm.PatientLoadFound(data:) ->
          mm.PatientLoadFound(mm.PatientData(..data, patient: updated_patient))
        _ -> patient
      }
      let model =
        model
        |> set_form_state(id:, patient: new_pat, formstate: mm.FormStateNone)
      #(model, effect.none())
    }
  }
}

fn telecom_value(
  telecom: List(r4us.Contactpoint),
  system: r4us_valuesets.Contactpointsystem,
) -> String {
  telecom
  |> list.find(fn(cp) { cp.system == Some(system) })
  |> result.try(fn(cp) { option.to_result(cp.value, Nil) })
  |> result.unwrap("")
}

pub fn edit(model: Model) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id: pat_id, patient:, page: _) ->
      case patient {
        mm.PatientLoadFound(data) -> {
          let pat = data.patient
          let gender = case pat.gender {
            Some(g) -> r4us_valuesets.administrativegender_to_string(g)
            None -> ""
          }
          let birthdate = case pat.birth_date {
            Some(bd) -> primitive_types.date_to_string(bd)
            None -> ""
          }
          let phone =
            telecom_value(pat.telecom, r4us_valuesets.ContactpointsystemPhone)
          let email =
            telecom_value(pat.telecom, r4us_valuesets.ContactpointsystemEmail)
          let race = case pat.us_core_race {
            [first, ..] -> first.text
            [] -> ""
          }
          let ethnicity = case pat.us_core_ethnicity {
            [first, ..] -> first.text
            [] -> ""
          }
          let first_address = case pat.address {
            [first, ..] -> first
            [] -> r4us.address_new()
          }
          let address_line = case first_address.line {
            [l, ..] -> l
            [] -> ""
          }
          let address_city = option.unwrap(first_address.city, "")
          let address_state = option.unwrap(first_address.state, "")
          let address_postal_code = option.unwrap(first_address.postal_code, "")
          let active = case pat.active {
            Some(True) -> "yes"
            Some(False) -> "no"
            None -> ""
          }
          let marital_status = case pat.marital_status {
            Some(cc) ->
              case cc.text {
                Some(t) -> t
                None ->
                  case cc.coding {
                    [c, ..] -> option.unwrap(c.display, "")
                    [] -> ""
                  }
              }
            None -> ""
          }
          let deceased = case pat.deceased {
            Some(r4us.PatientDeceasedBoolean(True)) -> "yes"
            Some(r4us.PatientDeceasedBoolean(False)) -> "no"
            Some(r4us.PatientDeceasedDatetime(_)) -> "yes"
            None -> ""
          }
          let first_contact = case pat.contact {
            [c, ..] -> c
            [] -> r4us.patient_contact_new()
          }
          let contact_name = case first_contact.name {
            Some(hn) -> utils.humanname_to_string(hn)
            None -> ""
          }
          let contact_phone =
            telecom_value(
              first_contact.telecom,
              r4us_valuesets.ContactpointsystemPhone,
            )
          let contact_email =
            telecom_value(
              first_contact.telecom,
              r4us_valuesets.ContactpointsystemEmail,
            )

          patient_schema(pat)
          |> form.new
          |> add_name_fields(pat.name)
          |> add_recorded_gender_fields(pat.individual_recorded_sex_or_gender)
          |> form.add_string("gender", gender)
          |> form.add_string("birthdate", birthdate)
          |> add_identifier_fields(pat.identifier)
          |> form.add_string("phone", phone)
          |> form.add_string("email", email)
          |> form.add_string("race", race)
          |> form.add_string("ethnicity", ethnicity)
          |> form.add_string("address_line", address_line)
          |> form.add_string("address_city", address_city)
          |> form.add_string("address_state", address_state)
          |> form.add_string("address_postal_code", address_postal_code)
          |> form.add_string("active", active)
          |> form.add_string("marital_status", marital_status)
          |> form.add_string("deceased", deceased)
          |> form.add_string("contact_name", contact_name)
          |> form.add_string("contact_phone", contact_phone)
          |> form.add_string("contact_email", contact_email)
          |> form_to_model(model, pat_id, patient)
        }
        _ -> #(model, effect.none())
      }
  }
}

pub fn form_to_model(demo_form, model, pat_id, patient) {
  let demo_form = demo_form |> mm.FormStateSome |> mm.PatientDemographics
  let route = mm.RoutePatient(id: pat_id, patient:, page: demo_form)
  let model = Model(..model, route:)
  #(model, effect.none())
}

pub fn server_error(
  model: Model,
  submitted_form: Form(r4us.Patient),
  err: r4us_rsvp.Err,
) -> #(Model, Effect(a)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> {
      let demo_form =
        submitted_form
        |> form.add_error(
          patient_form_server_error_name,
          form.CustomError("Server error: " <> utils.err_to_string(err)),
        )
        |> mm.FormStateSome
        |> mm.PatientDemographics
      let route = mm.RoutePatient(id:, patient:, page: demo_form)
      #(Model(..model, route:), effect.none())
    }
  }
}

pub fn submit(model: Model, form_patient: r4us.Patient) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, patient:, page:) ->
      case patient {
        mm.PatientLoadFound(_) -> {
          let submitted_form = case page {
            mm.PatientDemographics(mm.FormStateSome(f)) -> f
            _ -> form.new(patient_schema(form_patient))
          }
          let effect =
            r4us_rsvp.patient_update(form_patient, model.client, fn(result) {
              mm.ServerUpdatedPatientDemographics(result, submitted_form)
            })
            |> result.unwrap(effect.none())
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
  let demo_form = mm.PatientDemographics(formstate)
  let route = mm.RoutePatient(id:, patient:, page: demo_form)
  Model(..model, route:)
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

pub fn form_errors(model: Model, err: Form(r4us.Patient)) {
  case model.route {
    mm.RouteNoId(_) -> #(model, effect.none())
    mm.RoutePatient(id:, page: _, patient:) -> #(
      Model(
        ..model,
        route: mm.RoutePatient(
          id:,
          page: mm.PatientDemographics(mm.FormStateSome(err)),
          patient:,
        ),
      ),
      effect.none(),
    )
  }
}

fn add_name(
  model: Model,
  values: List(#(String, String)),
) -> #(Model, Effect(a)) {
  case current_demographics_form(model) {
    Ok(#(pat_id, patient, demo_form)) -> {
      let count = submitted_name_count(values, 0) + 1
      let values = values |> values_with_name_count(count)
      let demo_form = demo_form |> form.set_values(values)
      #(
        model
          |> set_form_state(
            id: pat_id,
            patient:,
            formstate: mm.FormStateSome(demo_form),
          ),
        effect.none(),
      )
    }
    Error(_) -> #(model, effect.none())
  }
}

fn delete_name(
  model: Model,
  values: List(#(String, String)),
) -> #(Model, Effect(a)) {
  case current_demographics_form(model) {
    Ok(#(pat_id, patient, demo_form)) -> {
      let delete_index =
        submitted_value(values, "delete_name")
        |> int.parse
        |> result.unwrap(-1)
      let count = submitted_name_count(values, 0)
      let values = values |> values_without_name(delete_index, count)
      let demo_form = demo_form |> form.set_values(values)
      #(
        model
          |> set_form_state(
            id: pat_id,
            patient:,
            formstate: mm.FormStateSome(demo_form),
          ),
        effect.none(),
      )
    }
    Error(_) -> #(model, effect.none())
  }
}

fn add_recorded_gender(
  model: Model,
  values: List(#(String, String)),
) -> #(Model, Effect(a)) {
  case current_demographics_form(model) {
    Ok(#(pat_id, patient, demo_form)) -> {
      let count = submitted_recorded_gender_count(values, 0) + 1
      let values = values |> values_with_recorded_gender_count(count)
      let demo_form = demo_form |> form.set_values(values)
      #(
        model
          |> set_form_state(
            id: pat_id,
            patient:,
            formstate: mm.FormStateSome(demo_form),
          ),
        effect.none(),
      )
    }
    Error(_) -> #(model, effect.none())
  }
}

fn delete_recorded_gender(
  model: Model,
  values: List(#(String, String)),
) -> #(Model, Effect(a)) {
  case current_demographics_form(model) {
    Ok(#(pat_id, patient, demo_form)) -> {
      let delete_index =
        submitted_value(values, "delete_recorded_gender")
        |> int.parse
        |> result.unwrap(-1)
      let count = submitted_recorded_gender_count(values, 0)
      let values = values |> values_without_recorded_gender(delete_index, count)
      let demo_form = demo_form |> form.set_values(values)
      #(
        model
          |> set_form_state(
            id: pat_id,
            patient:,
            formstate: mm.FormStateSome(demo_form),
          ),
        effect.none(),
      )
    }
    Error(_) -> #(model, effect.none())
  }
}

fn add_identifier(
  model: Model,
  values: List(#(String, String)),
) -> #(Model, Effect(a)) {
  case current_demographics_form(model) {
    Ok(#(pat_id, patient, demo_form)) -> {
      let count = submitted_identifier_count(values, 0) + 1
      let values = values |> values_with_identifier_count(count)
      let demo_form = demo_form |> form.set_values(values)
      #(
        model
          |> set_form_state(
            id: pat_id,
            patient:,
            formstate: mm.FormStateSome(demo_form),
          ),
        effect.none(),
      )
    }
    Error(_) -> #(model, effect.none())
  }
}

fn delete_identifier(
  model: Model,
  values: List(#(String, String)),
) -> #(Model, Effect(a)) {
  case current_demographics_form(model) {
    Ok(#(pat_id, patient, demo_form)) -> {
      let delete_index =
        submitted_value(values, "delete_identifier")
        |> int.parse
        |> result.unwrap(-1)
      let count = submitted_identifier_count(values, 0)
      let values = values |> values_without_identifier(delete_index, count)
      let demo_form = demo_form |> form.set_values(values)
      #(
        model
          |> set_form_state(
            id: pat_id,
            patient:,
            formstate: mm.FormStateSome(demo_form),
          ),
        effect.none(),
      )
    }
    Error(_) -> #(model, effect.none())
  }
}

fn current_demographics_form(
  model: Model,
) -> Result(#(String, mm.PatientLoad, Form(r4us.Patient)), Nil) {
  case model.route {
    mm.RouteNoId(_) -> Error(Nil)
    mm.RoutePatient(id:, patient:, page:) ->
      case page {
        mm.PatientDemographics(mm.FormStateSome(demo_form)) ->
          Ok(#(id, patient, demo_form))
        _ -> Error(Nil)
      }
  }
}

fn submitted_value(values: List(#(String, String)), name: String) -> String {
  values |> list.key_find(name) |> result.unwrap("")
}

fn submitted_name_count(values: List(#(String, String)), fallback: Int) -> Int {
  submitted_value(values, name_count_name)
  |> parse_unbounded_count_string(fallback)
}

fn submitted_recorded_gender_count(
  values: List(#(String, String)),
  fallback: Int,
) -> Int {
  submitted_value(values, recorded_gender_count_name)
  |> parse_unbounded_count_string(fallback)
}

fn submitted_identifier_count(
  values: List(#(String, String)),
  fallback: Int,
) -> Int {
  submitted_value(values, identifier_count_name)
  |> parse_identifier_count_string(fallback)
}

fn parse_unbounded_count_string(count_string: String, fallback: Int) -> Int {
  let count = count_string |> int.parse |> result.unwrap(fallback)
  case count < 0 {
    True -> 0
    False -> count
  }
}

fn values_with_name_count(
  values: List(#(String, String)),
  count: Int,
) -> List(#(String, String)) {
  let count = parse_unbounded_count_string(int.to_string(count), 0)
  [
    #(name_count_name, int.to_string(count)),
    ..values
    |> list.filter(fn(pair) {
      pair.0 != name_count_name
      && pair.0 != "add_name"
      && pair.0 != "delete_name"
    })
  ]
}

pub fn form_add_name(
  demo_form: Form(r4us.Patient),
  values: List(#(String, String)),
) -> Form(r4us.Patient) {
  let count = submitted_name_count(values, 0) + 1
  let values = values |> values_with_name_count(count)
  demo_form |> form.set_values(values)
}

fn values_with_recorded_gender_count(
  values: List(#(String, String)),
  count: Int,
) -> List(#(String, String)) {
  let count = parse_unbounded_count_string(int.to_string(count), 0)
  [
    #(recorded_gender_count_name, int.to_string(count)),
    ..values
    |> list.filter(fn(pair) {
      pair.0 != recorded_gender_count_name
      && pair.0 != "add_recorded_gender"
      && pair.0 != "delete_recorded_gender"
    })
  ]
}

fn values_without_recorded_gender(
  values: List(#(String, String)),
  delete_index: Int,
  count: Int,
) -> List(#(String, String)) {
  let count = parse_unbounded_count_string(int.to_string(count), 0)
  case delete_index < 0 || delete_index >= count {
    True -> values_with_recorded_gender_count(values, count)
    False -> {
      let base_values =
        values
        |> list.filter(fn(pair) {
          pair.0 != recorded_gender_count_name
          && pair.0 != "add_recorded_gender"
          && pair.0 != "delete_recorded_gender"
          && !string.starts_with(pair.0, "recorded_gender_")
        })
      let recorded_gender_values =
        shifted_recorded_gender_values(values, count, delete_index, 0, 0, [])
      [
        #(recorded_gender_count_name, int.to_string(count - 1)),
        ..list.append(base_values, recorded_gender_values)
      ]
    }
  }
}

pub fn form_add_recorded_gender(
  demo_form: Form(r4us.Patient),
  values: List(#(String, String)),
) -> Form(r4us.Patient) {
  let count = submitted_recorded_gender_count(values, 0) + 1
  let values = values |> values_with_recorded_gender_count(count)
  demo_form |> form.set_values(values)
}

pub fn form_delete_recorded_gender(
  demo_form: Form(r4us.Patient),
  values: List(#(String, String)),
) -> Form(r4us.Patient) {
  let count = submitted_recorded_gender_count(values, 0)
  let delete_index =
    submitted_value(values, "delete_recorded_gender")
    |> parse_unbounded_count_string(-1)
  let values = values |> values_without_recorded_gender(delete_index, count)
  demo_form |> form.set_values(values)
}

fn shifted_recorded_gender_values(
  values: List(#(String, String)),
  count: Int,
  delete_index: Int,
  read_index: Int,
  write_index: Int,
  acc: List(#(String, String)),
) -> List(#(String, String)) {
  case read_index >= count {
    True -> list.reverse(acc)
    False ->
      case read_index == delete_index {
        True ->
          shifted_recorded_gender_values(
            values,
            count,
            delete_index,
            read_index + 1,
            write_index,
            acc,
          )
        False ->
          shifted_recorded_gender_values(
            values,
            count,
            delete_index,
            read_index + 1,
            write_index + 1,
            [
              #(
                recorded_gender_value_name(write_index),
                submitted_value(values, recorded_gender_value_name(read_index)),
              ),
              #(
                recorded_gender_type_name(write_index),
                submitted_value(values, recorded_gender_type_name(read_index)),
              ),
              #(
                recorded_gender_effective_start_name(write_index),
                submitted_value(
                  values,
                  recorded_gender_effective_start_name(read_index),
                ),
              ),
              #(
                recorded_gender_effective_end_name(write_index),
                submitted_value(
                  values,
                  recorded_gender_effective_end_name(read_index),
                ),
              ),
              #(
                recorded_gender_comment_name(write_index),
                submitted_value(
                  values,
                  recorded_gender_comment_name(read_index),
                ),
              ),
              ..acc
            ],
          )
      }
  }
}

fn values_without_name(
  values: List(#(String, String)),
  delete_index: Int,
  count: Int,
) -> List(#(String, String)) {
  let count = parse_unbounded_count_string(int.to_string(count), 0)
  case delete_index < 0 || delete_index >= count {
    True -> values_with_name_count(values, count)
    False -> {
      let base_values =
        values
        |> list.filter(fn(pair) {
          pair.0 != name_count_name
          && pair.0 != "add_name"
          && pair.0 != "delete_name"
          && !string.starts_with(pair.0, "name_")
        })
      let name_values =
        shifted_name_values(values, count, delete_index, 0, 0, [])
      [
        #(name_count_name, int.to_string(count - 1)),
        ..list.append(base_values, name_values)
      ]
    }
  }
}

pub fn form_delete_name(
  demo_form: Form(r4us.Patient),
  values: List(#(String, String)),
) -> Form(r4us.Patient) {
  let count = submitted_name_count(values, 0)
  let delete_index =
    submitted_value(values, "delete_name")
    |> parse_unbounded_count_string(-1)
  let values = values |> values_without_name(delete_index, count)
  demo_form |> form.set_values(values)
}

fn shifted_name_values(
  values: List(#(String, String)),
  count: Int,
  delete_index: Int,
  read_index: Int,
  write_index: Int,
  acc: List(#(String, String)),
) -> List(#(String, String)) {
  case read_index >= count {
    True -> list.reverse(acc)
    False ->
      case read_index == delete_index {
        True ->
          shifted_name_values(
            values,
            count,
            delete_index,
            read_index + 1,
            write_index,
            acc,
          )
        False ->
          shifted_name_values(
            values,
            count,
            delete_index,
            read_index + 1,
            write_index + 1,
            [
              #(
                name_given_name(write_index),
                submitted_value(values, name_given_name(read_index)),
              ),
              #(
                name_family_name(write_index),
                submitted_value(values, name_family_name(read_index)),
              ),
              #(
                name_period_start_name(write_index),
                submitted_value(values, name_period_start_name(read_index)),
              ),
              #(
                name_period_end_name(write_index),
                submitted_value(values, name_period_end_name(read_index)),
              ),
              ..acc
            ],
          )
      }
  }
}

fn values_with_identifier_count(
  values: List(#(String, String)),
  count: Int,
) -> List(#(String, String)) {
  let count = clamp_identifier_count(count)
  [
    #(identifier_count_name, int.to_string(count)),
    ..values
    |> list.filter(fn(pair) {
      pair.0 != identifier_count_name
      && pair.0 != "add_identifier"
      && pair.0 != "delete_identifier"
    })
  ]
}

pub fn form_add_identifier(
  demo_form: Form(r4us.Patient),
  values: List(#(String, String)),
) -> Form(r4us.Patient) {
  let count = submitted_identifier_count(values, 0) + 1
  let values = values |> values_with_identifier_count(count)
  demo_form |> form.set_values(values)
}

fn values_without_identifier(
  values: List(#(String, String)),
  delete_index: Int,
  count: Int,
) -> List(#(String, String)) {
  let count = clamp_identifier_count(count)
  case delete_index < 0 || delete_index >= count {
    True -> values_with_identifier_count(values, count)
    False -> {
      let base_values =
        values
        |> list.filter(fn(pair) {
          pair.0 != identifier_count_name
          && pair.0 != "add_identifier"
          && pair.0 != "delete_identifier"
          && !string.starts_with(pair.0, "identifier_")
        })
      let identifier_values =
        shifted_identifier_values(values, count, delete_index, 0, 0, [])
      [
        #(identifier_count_name, int.to_string(count - 1)),
        ..list.append(base_values, identifier_values)
      ]
    }
  }
}

pub fn form_delete_identifier(
  demo_form: Form(r4us.Patient),
  values: List(#(String, String)),
) -> Form(r4us.Patient) {
  let count = submitted_identifier_count(values, 0)
  let delete_index =
    submitted_value(values, "delete_identifier")
    |> parse_identifier_count_string(-1)
  let values = values |> values_without_identifier(delete_index, count)
  demo_form |> form.set_values(values)
}

fn shifted_identifier_values(
  values: List(#(String, String)),
  count: Int,
  delete_index: Int,
  read_index: Int,
  write_index: Int,
  acc: List(#(String, String)),
) -> List(#(String, String)) {
  case read_index >= count {
    True -> list.reverse(acc)
    False ->
      case read_index == delete_index {
        True ->
          shifted_identifier_values(
            values,
            count,
            delete_index,
            read_index + 1,
            write_index,
            acc,
          )
        False -> {
          let sys = submitted_value(values, identifier_system_name(read_index))
          let val = submitted_value(values, identifier_value_name(read_index))
          shifted_identifier_values(
            values,
            count,
            delete_index,
            read_index + 1,
            write_index + 1,
            [
              #(identifier_system_name(write_index), sys),
              #(identifier_value_name(write_index), val),
              ..acc
            ],
          )
        }
      }
  }
}

const race_codings: List(#(String, String)) = [
  #("1002-5", "American Indian or Alaska Native"),
  #("2028-9", "Asian"),
  #("2054-5", "Black or African American"),
  #("2076-8", "Native Hawaiian or Other Pacific Islander"),
  #("2106-3", "White"),
]

const ethnicity_codings: List(#(String, String)) = [
  #("2135-2", "Hispanic or Latino"),
  #("2186-5", "Not Hispanic or Latino"),
]

const marital_codings: List(#(String, String)) = [
  #("M", "Married"),
  #("S", "Never Married"),
  #("D", "Divorced"),
  #("W", "Widowed"),
  #("L", "Legally Separated"),
  #("P", "Domestic Partner"),
]

const name_count_name = "name_count"

const recorded_gender_count_name = "recorded_gender_count"

pub const patient_form_server_error_name = "server_error"

fn add_name_fields(demo_form, names: List(r4us.Humanname)) {
  let initial_count = case names == [] {
    True -> 1
    False -> list.length(names)
  }
  list.index_fold(
    names,
    demo_form |> form.add_string(name_count_name, int.to_string(initial_count)),
    fn(f, name, index) {
      f
      |> form.add_string(name_given_name(index), first_given(name))
      |> form.add_string(
        name_family_name(index),
        option.unwrap(name.family, ""),
      )
      |> form.add_string(
        name_period_start_name(index),
        period_start_string(name),
      )
      |> form.add_string(name_period_end_name(index), period_end_string(name))
    },
  )
}

fn first_given(name: r4us.Humanname) -> String {
  case name.given {
    [given, ..] -> given
    [] -> ""
  }
}

fn period_start_string(name: r4us.Humanname) -> String {
  case name.period {
    Some(period) ->
      period.start
      |> option.map(primitive_types.datetime_to_string)
      |> option.unwrap("")
    None -> ""
  }
}

fn period_end_string(name: r4us.Humanname) -> String {
  case name.period {
    Some(period) ->
      period.end
      |> option.map(primitive_types.datetime_to_string)
      |> option.unwrap("")
    None -> ""
  }
}

fn name_given_name(index: Int) -> String {
  "name_" <> int.to_string(index) <> "_given"
}

fn name_family_name(index: Int) -> String {
  "name_" <> int.to_string(index) <> "_family"
}

fn name_period_start_name(index: Int) -> String {
  "name_" <> int.to_string(index) <> "_period_start"
}

fn name_period_end_name(index: Int) -> String {
  "name_" <> int.to_string(index) <> "_period_end"
}

fn parse_name_slots(
  existing: List(r4us.Humanname),
  index: Int,
  count: Int,
  acc: List(r4us.Humanname),
  continuation: fn(List(r4us.Humanname)) -> form.Schema(r4us.Patient),
) -> form.Schema(r4us.Patient) {
  case index >= count {
    True -> continuation(list.reverse(acc))
    False -> {
      use given <- form.field(name_given_name(index), form.parse_string)
      use family <- form.field(name_family_name(index), form.parse_string)
      use period_start <- form.field(
        name_period_start_name(index),
        form.parse_string,
      )
      use period_end <- form.field(
        name_period_end_name(index),
        form.parse_string,
      )
      let new_acc = case
        given == "" && family == "" && period_start == "" && period_end == ""
      {
        True -> acc
        False -> {
          let existing_at_i = case list.drop(existing, index) {
            [first, ..] -> first
            [] -> r4us.humanname_new()
          }
          [
            r4us.Humanname(
              ..existing_at_i,
              given: case given {
                "" -> []
                _ -> [given]
              },
              family: option_string(family),
              period: period_from_strings(period_start, period_end),
            ),
            ..acc
          ]
        }
      }
      parse_name_slots(existing, index + 1, count, new_acc, continuation)
    }
  }
}

fn period_from_strings(start: String, end: String) -> Option(r4us.Period) {
  let start_dt = optional_datetime(start)
  let end_dt = optional_datetime(end)
  case start_dt, end_dt {
    None, None -> None
    _, _ -> Some(r4us.Period(..r4us.period_new(), start: start_dt, end: end_dt))
  }
}

fn optional_datetime(value: String) {
  case value {
    "" -> None
    _ ->
      value
      |> primitive_types.parse_datetime
      |> result.map(Some)
      |> result.unwrap(None)
  }
}

fn option_string(value: String) -> Option(String) {
  case value {
    "" -> None
    _ -> Some(value)
  }
}

fn name_form_section(demo_form, index: Int) {
  let label = "name " <> int.to_string(index + 1)
  h.fieldset(
    [
      a.class(
        "w-full border "
        <> colors.border_surface_0
        <> " rounded p-2 flex flex-wrap gap-4",
      ),
    ],
    [
      h.legend([a.class("px-2 text-xs " <> colors.subtext_1)], [
        h.text(label),
      ]),
      view_form_input_wide(
        demo_form,
        is: "text",
        name: name_given_name(index),
        label: "first",
      ),
      view_form_input_wide(
        demo_form,
        is: "text",
        name: name_family_name(index),
        label: "last",
      ),
      view_form_input(
        demo_form,
        is: "date",
        name: name_period_start_name(index),
        label: "start",
      ),
      view_form_input(
        demo_form,
        is: "date",
        name: name_period_end_name(index),
        label: "end",
      ),
      h.div([a.class("flex items-end")], [
        h.button(
          [
            a.type_("submit"),
            a.name("delete_name"),
            a.value(int.to_string(index)),
            ..btn_attrs()
          ],
          [h.text("Delete")],
        ),
      ]),
    ],
  )
}

fn add_recorded_gender_fields(
  demo_form,
  recorded_genders: List(r4us.IndividualRecordedsexorgender),
) {
  list.index_fold(
    recorded_genders,
    demo_form
      |> form.add_string(
        recorded_gender_count_name,
        int.to_string(list.length(recorded_genders)),
      ),
    fn(f, recorded_gender, index) {
      f
      |> form.add_string(
        recorded_gender_value_name(index),
        utils.codeableconcept_to_string(recorded_gender.value),
      )
      |> form.add_string(
        recorded_gender_type_name(index),
        recorded_gender.type_
          |> option.map(utils.codeableconcept_to_string)
          |> option.unwrap(""),
      )
      |> form.add_string(
        recorded_gender_effective_start_name(index),
        case recorded_gender.effective_period {
          Some(period) ->
            period.start
            |> option.map(primitive_types.datetime_to_string)
            |> option.unwrap("")
          None -> ""
        },
      )
      |> form.add_string(
        recorded_gender_effective_end_name(index),
        case recorded_gender.effective_period {
          Some(period) ->
            period.end
            |> option.map(primitive_types.datetime_to_string)
            |> option.unwrap("")
          None -> ""
        },
      )
      |> form.add_string(
        recorded_gender_comment_name(index),
        option.unwrap(recorded_gender.comment, ""),
      )
    },
  )
}

fn recorded_gender_value_name(index: Int) -> String {
  "recorded_gender_" <> int.to_string(index) <> "_value"
}

fn recorded_gender_type_name(index: Int) -> String {
  "recorded_gender_" <> int.to_string(index) <> "_type"
}

fn recorded_gender_effective_start_name(index: Int) -> String {
  "recorded_gender_" <> int.to_string(index) <> "_effective_start"
}

fn recorded_gender_effective_end_name(index: Int) -> String {
  "recorded_gender_" <> int.to_string(index) <> "_effective_end"
}

fn recorded_gender_comment_name(index: Int) -> String {
  "recorded_gender_" <> int.to_string(index) <> "_comment"
}

fn recorded_gender_value_options(current_value: String) -> List(String) {
  let options = list.map(genderidentity.codes, fn(code) { code.2 })
  case current_value == "" || list.contains(options, current_value) {
    True -> options
    False -> [current_value, ..options]
  }
}

fn recorded_gender_codeableconcept(display: String) -> r4us.Codeableconcept {
  case list.find(genderidentity.codes, fn(code) { code.2 == display }) {
    Ok(#(code, system, label)) ->
      r4us.Codeableconcept(
        ..r4us.codeableconcept_new(),
        text: Some(label),
        coding: [utils.coding(code:, system:, display: label)],
      )
    Error(_) ->
      r4us.Codeableconcept(
        ..r4us.codeableconcept_new(),
        text: option_string(display),
      )
  }
}

fn parse_recorded_gender_slots(
  existing: List(r4us.IndividualRecordedsexorgender),
  index: Int,
  count: Int,
  acc: List(r4us.IndividualRecordedsexorgender),
  continuation: fn(List(r4us.IndividualRecordedsexorgender)) ->
    form.Schema(r4us.Patient),
) -> form.Schema(r4us.Patient) {
  case index >= count {
    True -> continuation(list.reverse(acc))
    False -> {
      use value <- form.field(
        recorded_gender_value_name(index),
        form.parse_string,
      )
      use type_ <- form.field(
        recorded_gender_type_name(index),
        form.parse_string,
      )
      use effective_start <- form.field(
        recorded_gender_effective_start_name(index),
        form.parse_string,
      )
      use effective_end <- form.field(
        recorded_gender_effective_end_name(index),
        form.parse_string,
      )
      use comment <- form.field(
        recorded_gender_comment_name(index),
        form.parse_string,
      )
      let new_acc = case
        value == ""
        && type_ == ""
        && effective_start == ""
        && effective_end == ""
        && comment == ""
      {
        True -> acc
        False -> {
          let existing_at_i = case list.drop(existing, index) {
            [first, ..] -> first
            [] ->
              r4us.IndividualRecordedsexorgender(
                value: r4us.codeableconcept_new(),
                type_: None,
                effective_period: None,
                acquisition_date: None,
                source: None,
                source_document: None,
                source_field: None,
                jurisdiction: None,
                comment: None,
                gender_element_qualifier: None,
              )
          }
          [
            r4us.IndividualRecordedsexorgender(
              ..existing_at_i,
              value: recorded_gender_codeableconcept(value),
              type_: case type_ {
                "" -> None
                _ ->
                  Some(
                    r4us.Codeableconcept(
                      ..r4us.codeableconcept_new(),
                      text: Some(type_),
                    ),
                  )
              },
              effective_period: period_from_strings(
                effective_start,
                effective_end,
              ),
              comment: option_string(comment),
            ),
            ..acc
          ]
        }
      }
      parse_recorded_gender_slots(
        existing,
        index + 1,
        count,
        new_acc,
        continuation,
      )
    }
  }
}

fn recorded_gender_form_section(demo_form, index: Int) {
  let value_name = recorded_gender_value_name(index)
  let current_value = form.field_value(demo_form, value_name)
  let label = "recorded gender " <> int.to_string(index + 1)
  h.fieldset(
    [
      a.class(
        "w-full border "
        <> colors.border_surface_0
        <> " rounded p-2 flex flex-wrap gap-4",
      ),
    ],
    [
      h.legend([a.class("px-2 text-xs " <> colors.subtext_1)], [
        h.text(label),
      ]),
      view_form_select(
        demo_form,
        name: value_name,
        options: recorded_gender_value_options(current_value),
        label: "value",
      ),
      view_form_input_wide(
        demo_form,
        is: "text",
        name: recorded_gender_type_name(index),
        label: "type",
      ),
      view_form_input(
        demo_form,
        is: "date",
        name: recorded_gender_effective_start_name(index),
        label: "start",
      ),
      view_form_input(
        demo_form,
        is: "date",
        name: recorded_gender_effective_end_name(index),
        label: "end",
      ),
      view_form_input_wide(
        demo_form,
        is: "text",
        name: recorded_gender_comment_name(index),
        label: "comment",
      ),
      h.div([a.class("flex items-end")], [
        h.button(
          [
            a.type_("submit"),
            a.name("delete_recorded_gender"),
            a.value(int.to_string(index)),
            ..btn_attrs()
          ],
          [h.text("Delete")],
        ),
      ]),
    ],
  )
}

fn recorded_gender_form_fieldset(
  recorded_gender_sections: List(element.Element(msg)),
  add_recorded_gender_button,
) {
  h.fieldset(
    [
      a.class(
        "w-full border "
        <> colors.border_surface_0
        <> " rounded-lg p-4 flex flex-row flex-wrap gap-4",
      ),
    ],
    [
      h.legend([a.class("px-2 text-sm font-bold " <> colors.text)], [
        h.text("Recorded Gender"),
      ]),
      ..list.append(recorded_gender_sections, [
        h.div([a.class("w-full flex justify-start")], [
          add_recorded_gender_button,
        ]),
      ])
    ],
  )
}

fn recorded_gender_to_string(
  recorded_gender: r4us.IndividualRecordedsexorgender,
) -> String {
  let parts =
    [
      Some(utils.codeableconcept_to_string(recorded_gender.value)),
      recorded_gender.type_
        |> option.map(utils.codeableconcept_to_string)
        |> option.map(fn(text) { "type: " <> text }),
      recorded_gender.effective_period
        |> option.map(fn(period) {
          let start =
            period.start
            |> option.map(primitive_types.datetime_to_string)
            |> option.unwrap("?")
          let end =
            period.end
            |> option.map(primitive_types.datetime_to_string)
            |> option.unwrap("?")
          "period: " <> start <> " - " <> end
        }),
      recorded_gender.comment |> option.map(fn(text) { "comment: " <> text }),
    ]
    |> option.values
  case parts {
    [] -> ""
    _ -> string.join(parts, " · ")
  }
}

fn race_coding_for_display(display: String) -> r4us.Coding {
  case list.find(race_codings, fn(pair) { pair.1 == display }) {
    Ok(#(code, d)) ->
      utils.coding(code:, system: "urn:oid:2.16.840.1.113883.6.238", display: d)
    Error(_) ->
      utils.coding(
        code: "UNK",
        system: "http://terminology.hl7.org/CodeSystem/v3-NullFlavor",
        display: "Unknown",
      )
  }
}

fn ethnicity_coding_for_display(display: String) -> r4us.Coding {
  case list.find(ethnicity_codings, fn(pair) { pair.1 == display }) {
    Ok(#(code, d)) ->
      utils.coding(code:, system: "urn:oid:2.16.840.1.113883.6.238", display: d)
    Error(_) ->
      utils.coding(
        code: "UNK",
        system: "http://terminology.hl7.org/CodeSystem/v3-NullFlavor",
        display: "Unknown",
      )
  }
}

const max_identifier_slots = 20

const identifier_count_name = "identifier_count"

fn add_identifier_fields(demo_form, identifiers: List(r4us.Identifier)) {
  list.index_fold(
    identifiers,
    demo_form
      |> form.add_string(
        identifier_count_name,
        int.to_string(list.length(identifiers)),
      ),
    fn(f, ident, index) {
      let sys_name = identifier_system_name(index)
      let val_name = identifier_value_name(index)
      f
      |> form.add_string(sys_name, option.unwrap(ident.system, ""))
      |> form.add_string(val_name, option.unwrap(ident.value, ""))
    },
  )
}

fn identifier_system_name(index: Int) -> String {
  "identifier_" <> int.to_string(index) <> "_system"
}

fn identifier_value_name(index: Int) -> String {
  "identifier_" <> int.to_string(index) <> "_value"
}

fn parse_identifier_count_string(count_string: String, fallback: Int) -> Int {
  count_string
  |> int.parse
  |> result.unwrap(fallback)
  |> clamp_identifier_count
}

fn clamp_identifier_count(count: Int) -> Int {
  case count < 0 {
    True -> 0
    False ->
      case count > max_identifier_slots {
        True -> max_identifier_slots
        False -> count
      }
  }
}

fn parse_identifier_slots(
  existing: List(r4us.Identifier),
  index: Int,
  count: Int,
  acc: List(r4us.Identifier),
  continuation: fn(List(r4us.Identifier)) -> form.Schema(r4us.Patient),
) -> form.Schema(r4us.Patient) {
  case index >= count {
    True -> continuation(list.reverse(acc))
    False -> {
      let sys_name = identifier_system_name(index)
      let val_name = identifier_value_name(index)
      use system <- form.field(sys_name, form.parse_string)
      use value <- form.field(val_name, form.parse_string)
      let new_acc = case system == "" && value == "" {
        True -> acc
        False -> {
          let existing_at_i = case list.drop(existing, index) {
            [first, ..] -> first
            [] -> r4us.identifier_new()
          }
          let sys_opt = case system {
            "" -> None
            _ -> Some(system)
          }
          let val_opt = case value {
            "" -> None
            _ -> Some(value)
          }
          [
            r4us.Identifier(..existing_at_i, system: sys_opt, value: val_opt),
            ..acc
          ]
        }
      }
      parse_identifier_slots(existing, index + 1, count, new_acc, continuation)
    }
  }
}

fn identifier_form_section(demo_form, index: Int) {
  let sys_name = identifier_system_name(index)
  let val_name = identifier_value_name(index)
  let label = "identifier " <> int.to_string(index + 1)
  h.fieldset(
    [
      a.class(
        "w-full border "
        <> colors.border_surface_0
        <> " rounded p-2 flex flex-wrap gap-4",
      ),
    ],
    [
      h.legend([a.class("px-2 text-xs " <> colors.subtext_1)], [
        h.text(label),
      ]),
      view_form_input_wide(
        demo_form,
        is: "text",
        name: val_name,
        label: "value",
      ),
      view_form_input_wide(
        demo_form,
        is: "text",
        name: sys_name,
        label: "system",
      ),
      h.div([a.class("flex items-end")], [
        h.button(
          [
            a.type_("submit"),
            a.name("delete_identifier"),
            a.value(int.to_string(index)),
            ..btn_attrs()
          ],
          [h.text("Delete")],
        ),
      ]),
    ],
  )
}

fn marital_coding_for_display(display: String) -> Option(r4us.Coding) {
  case list.find(marital_codings, fn(pair) { pair.1 == display }) {
    Ok(#(code, d)) ->
      Some(utils.coding(
        code:,
        system: "http://terminology.hl7.org/CodeSystem/v3-MaritalStatus",
        display: d,
      ))
    Error(_) -> None
  }
}

pub fn patient_schema(pat: r4us.Patient) {
  use name_count_str <- form.field(name_count_name, form.parse_string)
  let name_count =
    parse_unbounded_count_string(name_count_str, list.length(pat.name))
  use name <- parse_name_slots(pat.name, 0, name_count, [])

  use recorded_gender_count_str <- form.field(
    recorded_gender_count_name,
    form.parse_string,
  )
  let recorded_gender_count =
    parse_unbounded_count_string(
      recorded_gender_count_str,
      list.length(pat.individual_recorded_sex_or_gender),
    )
  use individual_recorded_sex_or_gender <- parse_recorded_gender_slots(
    pat.individual_recorded_sex_or_gender,
    0,
    recorded_gender_count,
    [],
  )

  use gender_str <- form.field("gender", form.parse_string)
  let gender = case
    r4us_valuesets.administrativegender_from_string(gender_str)
  {
    Ok(g) -> Some(g)
    Error(_) -> None
  }

  use birthdate_str <- form.field("birthdate", form.parse_string)
  let birth_date = case birthdate_str {
    "" -> None
    _ ->
      case primitive_types.parse_date(birthdate_str) {
        Ok(bd) -> Some(bd)
        Error(_) -> None
      }
  }

  use identifier_count_str <- form.field(
    identifier_count_name,
    form.parse_string,
  )
  let identifier_count =
    parse_identifier_count_string(
      identifier_count_str,
      list.length(pat.identifier),
    )
  use identifier <- parse_identifier_slots(
    pat.identifier,
    0,
    identifier_count,
    [],
  )

  use phone <- form.field("phone", form.parse_string)
  use email <- form.field("email", form.parse_string)
  let telecom = case phone {
    "" -> []
    _ -> [
      r4us.Contactpoint(
        ..r4us.contactpoint_new(),
        system: Some(r4us_valuesets.ContactpointsystemPhone),
        value: Some(phone),
      ),
    ]
  }
  let telecom = case email {
    "" -> telecom
    _ -> [
      r4us.Contactpoint(
        ..r4us.contactpoint_new(),
        system: Some(r4us_valuesets.ContactpointsystemEmail),
        value: Some(email),
      ),
      ..telecom
    ]
  }

  use race_display <- form.field("race", form.parse_string)
  let us_core_race = case race_display {
    "" -> []
    _ -> [
      r4us.UsCoreRace(text: race_display, detailed: [], omb_category: [
        race_coding_for_display(race_display),
      ]),
    ]
  }

  use ethnicity_display <- form.field("ethnicity", form.parse_string)
  let us_core_ethnicity = case ethnicity_display {
    "" -> []
    _ -> [
      r4us.UsCoreEthnicity(
        text: ethnicity_display,
        detailed: [],
        omb_category: Some(ethnicity_coding_for_display(ethnicity_display)),
      ),
    ]
  }

  use address_line <- form.field("address_line", form.parse_string)
  use address_city <- form.field("address_city", form.parse_string)
  use address_state <- form.field("address_state", form.parse_string)
  use address_postal_code <- form.field(
    "address_postal_code",
    form.parse_string,
  )
  let empty_address =
    address_line == ""
    && address_city == ""
    && address_state == ""
    && address_postal_code == ""
  let existing_address = case pat.address {
    [first, ..] -> first
    [] -> r4us.address_new()
  }
  let rest_addresses = case pat.address {
    [_, ..rest] -> rest
    [] -> []
  }
  let address = case empty_address {
    True -> rest_addresses
    False -> [
      r4us.Address(
        ..existing_address,
        line: case address_line {
          "" -> []
          _ -> [address_line]
        },
        city: case address_city {
          "" -> None
          _ -> Some(address_city)
        },
        state: case address_state {
          "" -> None
          _ -> Some(address_state)
        },
        postal_code: case address_postal_code {
          "" -> None
          _ -> Some(address_postal_code)
        },
      ),
      ..rest_addresses
    ]
  }

  use active_str <- form.field("active", form.parse_string)
  let active = case active_str {
    "yes" -> Some(True)
    "no" -> Some(False)
    _ -> None
  }

  use marital_str <- form.field("marital_status", form.parse_string)
  let marital_status = case marital_str {
    "" -> None
    _ -> {
      let coding = case marital_coding_for_display(marital_str) {
        Some(c) -> [c]
        None -> []
      }
      Some(
        r4us.Codeableconcept(
          ..r4us.codeableconcept_new(),
          text: Some(marital_str),
          coding:,
        ),
      )
    }
  }

  use deceased_str <- form.field("deceased", form.parse_string)
  let deceased = case deceased_str {
    "yes" -> Some(r4us.PatientDeceasedBoolean(deceased: True))
    "no" -> Some(r4us.PatientDeceasedBoolean(deceased: False))
    _ -> None
  }

  use contact_name_str <- form.field("contact_name", form.parse_string)
  use contact_phone_str <- form.field("contact_phone", form.parse_string)
  use contact_email_str <- form.field("contact_email", form.parse_string)
  let contact_empty =
    contact_name_str == "" && contact_phone_str == "" && contact_email_str == ""
  let existing_contact = case pat.contact {
    [c, ..] -> c
    [] -> r4us.patient_contact_new()
  }
  let rest_contacts = case pat.contact {
    [_, ..rest] -> rest
    [] -> []
  }
  let contact = case contact_empty {
    True -> rest_contacts
    False -> {
      let contact_name = case contact_name_str {
        "" -> None
        _ ->
          Some(
            r4us.Humanname(..r4us.humanname_new(), text: Some(contact_name_str)),
          )
      }
      let contact_telecom = case contact_phone_str {
        "" -> []
        _ -> [
          r4us.Contactpoint(
            ..r4us.contactpoint_new(),
            system: Some(r4us_valuesets.ContactpointsystemPhone),
            value: Some(contact_phone_str),
          ),
        ]
      }
      let contact_telecom = case contact_email_str {
        "" -> contact_telecom
        _ -> [
          r4us.Contactpoint(
            ..r4us.contactpoint_new(),
            system: Some(r4us_valuesets.ContactpointsystemEmail),
            value: Some(contact_email_str),
          ),
          ..contact_telecom
        ]
      }
      [
        r4us.PatientContact(
          ..existing_contact,
          name: contact_name,
          telecom: contact_telecom,
          relationship: [],
        ),
        ..rest_contacts
      ]
    }
  }

  form.success(
    r4us.Patient(
      ..pat,
      name:,
      individual_recorded_sex_or_gender:,
      gender:,
      birth_date:,
      identifier:,
      telecom:,
      us_core_race:,
      us_core_ethnicity:,
      address:,
      active:,
      marital_status:,
      deceased:,
      contact:,
    ),
  )
}

pub fn view(data: mm.PatientData, demo_form: mm.FormState(r4us.Patient)) {
  let pat = data.patient
  [
    h.div([a.class("p-4 max-w-5xl")], [
      h.div([a.class("flex items-center gap-4 mb-4 min-h-12")], [
        h.h1([a.class("text-xl font-bold")], [h.text("Demographics")]),
        case demo_form {
          mm.FormStateNone ->
            btn("Edit", on_click: mm.UserClickedEditDemographics)
          _ -> element.none()
        },
      ]),
      case demo_form {
        mm.FormStateNone -> view_info(pat)
        mm.FormStateLoading -> h.p([], [h.text("loading...")])
        mm.FormStateSome(f) -> view_form(f, pat)
      },
    ]),
  ]
}

fn view_info(pat: r4us.Patient) {
  let names_display =
    h.div(
      [a.class("flex flex-col gap-1")],
      list.map(pat.name, fn(name) {
        h.div([], [h.text(utils.humanname_to_string(name))])
      }),
    )
  let gender = case pat.gender {
    Some(g) -> r4us_valuesets.administrativegender_to_string(g)
    None -> ""
  }
  let recorded_gender_display =
    h.div(
      [a.class("flex flex-col gap-1")],
      list.map(pat.individual_recorded_sex_or_gender, fn(recorded_gender) {
        h.div([], [h.text(recorded_gender_to_string(recorded_gender))])
      }),
    )
  let birth_date = case pat.birth_date {
    Some(bd) -> primitive_types.date_to_string(bd)
    None -> ""
  }
  let identifiers_display =
    h.div(
      [a.class("flex flex-col gap-1")],
      list.map(pat.identifier, fn(ident) {
        let val = option.unwrap(ident.value, "")
        let sys = option.unwrap(ident.system, "")
        let text = case sys {
          "" -> val
          _ -> val <> " (" <> sys <> ")"
        }
        h.div([], [h.text(text)])
      }),
    )
  let phone = telecom_value(pat.telecom, r4us_valuesets.ContactpointsystemPhone)
  let email = telecom_value(pat.telecom, r4us_valuesets.ContactpointsystemEmail)
  let race = case pat.us_core_race {
    [r, ..] -> r.text
    [] -> ""
  }
  let ethnicity = case pat.us_core_ethnicity {
    [e, ..] -> e.text
    [] -> ""
  }
  let address = case pat.address {
    [first, ..] -> {
      let line = string.join(first.line, " ")
      let city = option.unwrap(first.city, "")
      let state = option.unwrap(first.state, "")
      let zip = option.unwrap(first.postal_code, "")
      let locality =
        [city, state, zip]
        |> list.filter(fn(s) { s != "" })
        |> string.join(" ")
      [line, locality]
      |> list.filter(fn(s) { s != "" })
      |> string.join(", ")
    }
    [] -> ""
  }
  let active = case pat.active {
    Some(True) -> "Yes"
    Some(False) -> "No"
    None -> ""
  }
  let marital_status = case pat.marital_status {
    Some(cc) -> utils.codeableconcept_to_string(cc)
    None -> ""
  }
  let deceased = case pat.deceased {
    Some(r4us.PatientDeceasedBoolean(True)) -> "Yes"
    Some(r4us.PatientDeceasedBoolean(False)) -> "No"
    Some(r4us.PatientDeceasedDatetime(dt)) ->
      "Yes (" <> primitive_types.datetime_to_string(dt) <> ")"
    None -> ""
  }
  let emergency_contact = case pat.contact {
    [c, ..] -> {
      let cname = case c.name {
        Some(hn) -> utils.humanname_to_string(hn)
        None -> ""
      }
      let cphone =
        telecom_value(c.telecom, r4us_valuesets.ContactpointsystemPhone)
      let cemail =
        telecom_value(c.telecom, r4us_valuesets.ContactpointsystemEmail)
      let name_part = case cname {
        "" -> ""
        _ -> cname
      }
      let phone_part = case cphone {
        "" -> ""
        _ -> "phone: " <> cphone
      }
      let email_part = case cemail {
        "" -> ""
        _ -> "email: " <> cemail
      }
      [name_part, phone_part, email_part]
      |> list.filter(fn(part) { part != "" })
      |> string.join(" · ")
    }
    [] -> ""
  }
  h.div([], [
    h.div([a.class("flex gap-4 py-2 border-b " <> colors.border_surface_0)], [
      h.span([a.class("font-bold w-40 " <> colors.subtext_1)], [
        h.text("Names"),
      ]),
      names_display,
    ]),
    info_row("Gender", gender),
    h.div([a.class("flex gap-4 py-2 border-b " <> colors.border_surface_0)], [
      h.span([a.class("font-bold w-40 " <> colors.subtext_1)], [
        h.text("Recorded Genders"),
      ]),
      recorded_gender_display,
    ]),
    info_row("Birth Date", birth_date),
    h.div([a.class("flex gap-4 py-2 border-b " <> colors.border_surface_0)], [
      h.span([a.class("font-bold w-40 " <> colors.subtext_1)], [
        h.text("Identifiers"),
      ]),
      identifiers_display,
    ]),
    info_row("Phone", phone),
    info_row("Email", email),
    info_row("Race", race),
    info_row("Ethnicity", ethnicity),
    info_row("Address", address),
    info_row("Active", active),
    info_row("Marital Status", marital_status),
    info_row("Deceased", deceased),
    info_row("Emergency Contact", emergency_contact),
  ])
}

fn info_row(label: String, value: String) {
  h.div([a.class("flex gap-4 py-2 border-b " <> colors.border_surface_0)], [
    h.span([a.class("font-bold w-40 " <> colors.subtext_1)], [
      h.text(label),
    ]),
    h.span([], [h.text(value)]),
  ])
}

fn name_form_fieldset(
  name_sections: List(element.Element(msg)),
  add_name_button,
) {
  h.fieldset(
    [
      a.class(
        "w-full border "
        <> colors.border_surface_0
        <> " rounded-lg p-4 flex flex-row flex-wrap gap-4",
      ),
    ],
    [
      h.legend([a.class("px-2 text-sm font-bold " <> colors.text)], [
        h.text("Names"),
      ]),
      ..list.append(name_sections, [
        h.div([a.class("w-full flex justify-start")], [add_name_button]),
      ])
    ],
  )
}

fn identifier_form_fieldset(
  identifier_sections: List(element.Element(msg)),
  add_identifier_button,
) {
  h.fieldset(
    [
      a.class(
        "w-full border "
        <> colors.border_surface_0
        <> " rounded-lg p-4 flex flex-row flex-wrap gap-4",
      ),
    ],
    [
      h.legend([a.class("px-2 text-sm font-bold " <> colors.text)], [
        h.text("Identifiers"),
      ]),
      ..list.append(identifier_sections, [
        h.div([a.class("w-full flex justify-start")], [add_identifier_button]),
      ])
    ],
  )
}

pub fn view_patient_form(
  demo_form: Form(r4us.Patient),
  pat: r4us.Patient,
  title: String,
  submit_label: String,
  on_submit: fn(Result(r4us.Patient, Form(r4us.Patient))) -> msg,
  on_add_name: fn(List(#(String, String))) -> msg,
  on_delete_name: fn(List(#(String, String))) -> msg,
  on_add_recorded_gender: fn(List(#(String, String))) -> msg,
  on_delete_recorded_gender: fn(List(#(String, String))) -> msg,
  on_add_identifier: fn(List(#(String, String))) -> msg,
  on_delete_identifier: fn(List(#(String, String))) -> msg,
  cancel_button: Option(#(String, msg)),
) {
  let initial_name_count = case pat.name == [] {
    True -> 1
    False -> list.length(pat.name)
  }
  let name_count =
    form.field_value(demo_form, name_count_name)
    |> parse_unbounded_count_string(initial_name_count)
  let name_slots = list.repeat(0, times: name_count)
  let name_sections =
    list.index_map(name_slots, fn(_, i) { name_form_section(demo_form, i) })
  let add_name_button =
    h.button(
      [a.type_("submit"), a.name("add_name"), a.value("1"), ..btn_attrs()],
      [h.text("Add Another Name")],
    )
  let recorded_gender_count =
    form.field_value(demo_form, recorded_gender_count_name)
    |> parse_unbounded_count_string(list.length(
      pat.individual_recorded_sex_or_gender,
    ))
  let recorded_gender_slots = list.repeat(0, times: recorded_gender_count)
  let recorded_gender_sections =
    list.index_map(recorded_gender_slots, fn(_, i) {
      recorded_gender_form_section(demo_form, i)
    })
  let add_recorded_gender_button =
    h.button(
      [
        a.type_("submit"),
        a.name("add_recorded_gender"),
        a.value("1"),
        ..btn_attrs()
      ],
      [h.text("Add Recorded Gender")],
    )
  let identifier_count =
    form.field_value(demo_form, identifier_count_name)
    |> parse_identifier_count_string(list.length(pat.identifier))
  let identifier_slots = list.repeat(0, times: identifier_count)
  let identifier_sections =
    list.index_map(identifier_slots, fn(_, i) {
      identifier_form_section(demo_form, i)
    })
  let server_errors =
    form.field_error_messages(demo_form, patient_form_server_error_name)
  let add_identifier_button = case identifier_count >= max_identifier_slots {
    True -> element.none()
    False ->
      h.button(
        [
          a.type_("submit"),
          a.name("add_identifier"),
          a.value("1"),
          ..btn_attrs()
        ],
        [h.text("Add Another Identifier")],
      )
  }
  h.form(
    [
      event.on_submit(fn(values) {
        case submitted_value(values, "add_name") {
          "" ->
            case submitted_value(values, "delete_name") {
              "" ->
                case submitted_value(values, "add_recorded_gender") {
                  "" ->
                    case submitted_value(values, "delete_recorded_gender") {
                      "" ->
                        case submitted_value(values, "add_identifier") {
                          "" ->
                            case submitted_value(values, "delete_identifier") {
                              "" ->
                                demo_form
                                |> form.add_values(values)
                                |> form.run
                                |> on_submit
                              _ -> on_delete_identifier(values)
                            }
                          _ -> on_add_identifier(values)
                        }
                      _ -> on_delete_recorded_gender(values)
                    }
                  _ -> on_add_recorded_gender(values)
                }
              _ -> on_delete_name(values)
            }
          _ -> on_add_name(values)
        }
      }),
    ],
    [
      h.fieldset(
        [
          a.class(
            "border "
            <> colors.border_surface_0
            <> " rounded-lg p-4 flex flex-row flex-wrap gap-4",
          ),
        ],
        list.flatten([
          [
            h.legend(
              [a.class("px-2 text-sm font-bold " <> colors.text)],
              [
                h.text(title),
              ],
            ),
            h.input([
              a.type_("hidden"),
              a.name(identifier_count_name),
              a.value(int.to_string(identifier_count)),
            ]),
            h.input([
              a.type_("hidden"),
              a.name(name_count_name),
              a.value(int.to_string(name_count)),
            ]),
            h.input([
              a.type_("hidden"),
              a.name(recorded_gender_count_name),
              a.value(int.to_string(recorded_gender_count)),
            ]),
            case server_errors {
              [] -> element.none()
              errors ->
                h.div(
                  [
                    a.class("px-3 py-2 text-sm " <> colors.text_red_500_error),
                  ],
                  list.map(errors, h.text),
                )
            },
            name_form_fieldset(name_sections, add_name_button),
            view_form_select(
              demo_form,
              name: "gender",
              options: list.map(
                [
                  r4us_valuesets.AdministrativegenderMale,
                  r4us_valuesets.AdministrativegenderFemale,
                  r4us_valuesets.AdministrativegenderOther,
                  r4us_valuesets.AdministrativegenderUnknown,
                ],
                r4us_valuesets.administrativegender_to_string,
              ),
              label: "gender",
            ),
            view_form_input(
              demo_form,
              is: "date",
              name: "birthdate",
              label: "birth date",
            ),
          ],
          [
            recorded_gender_form_fieldset(
              recorded_gender_sections,
              add_recorded_gender_button,
            ),
          ],
          [identifier_form_fieldset(identifier_sections, add_identifier_button)],
          [
            view_form_input(demo_form, is: "tel", name: "phone", label: "phone"),
            view_form_input(
              demo_form,
              is: "email",
              name: "email",
              label: "email",
            ),
            view_form_select(
              demo_form,
              name: "race",
              options: list.map(race_codings, fn(pair) { pair.1 }),
              label: "race",
            ),
            view_form_select(
              demo_form,
              name: "ethnicity",
              options: list.map(ethnicity_codings, fn(pair) { pair.1 }),
              label: "ethnicity",
            ),
            view_form_input(
              demo_form,
              is: "text",
              name: "address_line",
              label: "address",
            ),
            view_form_input(
              demo_form,
              is: "text",
              name: "address_city",
              label: "city",
            ),
            view_form_input(
              demo_form,
              is: "text",
              name: "address_state",
              label: "state",
            ),
            view_form_input(
              demo_form,
              is: "text",
              name: "address_postal_code",
              label: "zip",
            ),
            view_form_select(
              demo_form,
              name: "active",
              options: ["yes", "no"],
              label: "active",
            ),
            view_form_select(
              demo_form,
              name: "marital_status",
              options: list.map(marital_codings, fn(pair) { pair.1 }),
              label: "marital status",
            ),
            view_form_select(
              demo_form,
              name: "deceased",
              options: ["yes", "no"],
              label: "deceased",
            ),
            view_form_input(
              demo_form,
              is: "text",
              name: "contact_name",
              label: "emergency contact name",
            ),
            view_form_input(
              demo_form,
              is: "tel",
              name: "contact_phone",
              label: "emergency contact phone",
            ),
            view_form_input(
              demo_form,
              is: "email",
              name: "contact_email",
              label: "emergency contact email",
            ),
            h.div([a.class("w-full flex justify-end gap-2")], [
              case cancel_button {
                Some(#(label, msg)) -> btn_cancel(label, on_click: msg)
                None -> element.none()
              },
              btn_nomsg(submit_label),
            ]),
          ],
        ]),
      ),
    ],
  )
}

fn view_form(demo_form: Form(r4us.Patient), pat: r4us.Patient) {
  view_patient_form(
    demo_form,
    pat,
    "Edit Demographics",
    "Save",
    mm.UserSubmittedDemographicsForm,
    mm.UserClickedAddDemographicsName,
    mm.UserClickedDeleteDemographicsName,
    mm.UserClickedAddDemographicsRecordedGender,
    mm.UserClickedDeleteDemographicsRecordedGender,
    mm.UserClickedAddDemographicsIdentifier,
    mm.UserClickedDeleteDemographicsIdentifier,
    Some(#("Cancel", mm.UserClickedCloseDemographicsForm)),
  )
}
