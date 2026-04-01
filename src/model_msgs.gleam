import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import lustre
import lustre/attribute.{type Attribute} as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/svg
import lustre/event
import modem
import utils.{opt_elt}

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model(
    client: r4us_rsvp.FhirClient,
    search: SearchPatient,
    route: Route,
    dragging_photo: Bool,
  )
}

pub type SearchPatient {
  SearchPatient(text: String, visible: Bool, results: SearchPatientResults)
}

pub type SearchPatientResults {
  SearchPatientResultsPats(pats: List(r4us.Patient))
  SearchPatientResultsErrMsg(err_msg: String)
  SearchPatientResultsLoadingMsg
  SearchPatientResultsEmptyMsg
}

// routes, uri_to_route type -> uri
// must stay in sync with Route uri -> type
// and in sync with labels in view

pub type Route {
  RoutePatient(id: String, patient: PatientLoad, page: RoutePatientPage)
  RouteNoId(page: RouteNoId)
}

pub type PatientLoad {
  PatientLoadStillLoading
  PatientLoadFound(data: PatientData)
  PatientLoadNotFound(String)
}

pub type PatientData {
  PatientData(
    patient: r4us.Patient,
    patient_allergy_new: r4us.Allergyintolerance,
    patient_allergies: List(r4us.Allergyintolerance),
    patient_medications: List(r4us.Medication),
    patient_observations: List(r4us.Observation),
  )
}

// while you could just stick these directly in route
// separating makes update easier to set model patient id
// without duplicating set id for each patient page
// plus guarantuee patient routes have a patient id
// a patient with that id existing is NOT guarantueed though
// model.patient is an option, might have a patient id that doesn't exist on server
// in which case show not found view
pub type RoutePatientPage {
  PatientOverview
  PatientAllergies
  PatientMedications
  PatientVitals
  PatientPhotos
}

// similarly when update goes to these routes
// can easily set model.pat_id to None without duplication
pub type RouteNoId {
  Index
  Settings
  RegisterPatient(newpatient: Form(r4us.Patient))
  NotFound(notfound: String)
}

pub fn href(route: Route) -> Attribute(msg) {
  route |> route_to_urlstring |> a.href
}

pub fn route_to_urlstring(route: Route) -> String {
  case route {
    RouteNoId(page:) ->
      case page {
        Index -> "/"
        Settings -> "/settings"
        RegisterPatient(_) -> "/registerpatient"
        NotFound(_) -> "/404"
      }
    RoutePatient(_patient, id:, page:) ->
      case page {
        PatientOverview -> "/patient/" <> id <> "/overview"
        PatientAllergies -> "/patient/" <> id <> "/allergies"
        PatientMedications -> "/patient/" <> id <> "/medications"
        PatientVitals -> "/patient/" <> id <> "/vitals"
        PatientPhotos -> "/patient/" <> id <> "/photos"
      }
  }
}

pub fn uri_to_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> RouteNoId(Index)
    ["settings"] -> RouteNoId(Settings)
    ["registerpatient"] ->
      RouteNoId(RegisterPatient(form.new(patient_schema())))
    ["patient", id, page] ->
      case page {
        "overview" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientOverview,
          )
        "allergies" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientAllergies,
          )
        "medications" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientMedications,
          )
        "vitals" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientVitals,
          )
        "photos" ->
          RoutePatient(
            id:,
            patient: PatientLoadStillLoading,
            page: PatientPhotos,
          )
        _ -> uri |> uri.to_string |> NotFound |> RouteNoId
      }
    _ -> uri |> uri.to_string |> NotFound |> RouteNoId
  }
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  UserNavigatedTo(route: Route)
  UserClickedChangeClient(String)
  UserFocusedSearch
  UserBlurredSearch
  UserSearchedPatient(String)
  ServerReturnedSearchPatients(Result(List(r4us.Patient), r4us_rsvp.Err))
  ServerReturnedPatientEverything(Result(r4us.Bundle, r4us_rsvp.Err))
  ServerCreatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerUpdatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerDeletedAllergy(Result(r4us.Operationoutcome, r4us_rsvp.Err))
  ServerUpdatedPatientPhoto(Result(r4us.Patient, r4us_rsvp.Err))
  UserTypedAllergyintoleranceNote(input: String, on_id: Option(String))
  UserClickedCreateAllergy
  UserSelectedPhotoEvent(dynamic.Dynamic)
  UserSelectedPhotoDataUrl(String)
  UserDraggingPhoto(Bool)
  UserClickedExistingPhoto(Int)
  UserClickedRegisterPatient(Result(r4us.Patient, Form(r4us.Patient)))
  ServerReturnedRegisterPatient(Result(r4us.Patient, r4us_rsvp.Err))
}

pub fn patient_schema() {
  use given <- form.field("first", form.parse_string)
  let given = case given {
    "" -> []
    _ -> [given]
  }
  use family <- form.field("last", form.parse_optional(form.parse_string))
  use birth_date <- form.field(
    "birthdate",
    form.parse_optional(form.parse_string),
  )
  use phone <- form.field("phone", form.parse_string)
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
  use email <- form.field("email", form.parse_string)
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
  use gender <- form.field("gender", form.parse_string)
  let gender = case r4us_valuesets.administrativegender_from_string(gender) {
    Ok(gender) -> Some(gender)
    Error(_) -> None
  }
  use race_display <- form.field("race", form.parse_string)
  let race = case race_display {
    "American Indian or Alaska Native" ->
      utils.coding(
        code: "1002-5",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "American Indian or Alaska Native",
      )
    "Asian" ->
      utils.coding(
        code: "2028-9",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Asian",
      )
    "Black or African American" ->
      utils.coding(
        code: "2054-5",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Black or African American",
      )
    "Native Hawaiian or Other Pacific Islander" ->
      utils.coding(
        code: "2076-8",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Native Hawaiian or Other Pacific Islander",
      )
    "White" ->
      utils.coding(
        code: "2106-3",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "White",
      )
    _ ->
      utils.coding(
        code: "UNK",
        system: "http://terminology.hl7.org/CodeSystem/v3-NullFlavor",
        display: "Unknown",
      )
  }
  let us_core_race = [
    r4us.UsCoreRace(text: race_display, detailed: [], omb_category: [race]),
  ]
  use address_line <- form.field(
    "address_line",
    form.parse_optional(form.parse_string),
  )
  use address_city <- form.field(
    "address_city",
    form.parse_optional(form.parse_string),
  )
  use address_state <- form.field(
    "address_state",
    form.parse_optional(form.parse_string),
  )
  use address_postal_code <- form.field(
    "address_postal_code",
    form.parse_optional(form.parse_string),
  )
  let address = case
    address_line,
    address_city,
    address_state,
    address_postal_code
  {
    None, None, None, None -> []
    _, _, _, _ -> [
      r4us.Address(
        ..r4us.address_new(),
        line: case address_line {
          Some(l) -> [l]
          None -> []
        },
        city: address_city,
        state: address_state,
        postal_code: address_postal_code,
      ),
    ]
  }
  use ethnicity_display <- form.field("ethnicity", form.parse_string)
  let ethnicity = case ethnicity_display {
    "Hispanic or Latino" ->
      utils.coding(
        code: "2135-2",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Hispanic or Latino",
      )
    "Not Hispanic or Latino" ->
      utils.coding(
        code: "2186-5",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Not Hispanic or Latino",
      )
    _ ->
      utils.coding(
        code: "UNK",
        system: "http://terminology.hl7.org/CodeSystem/v3-NullFlavor",
        display: "Unknown",
      )
  }
  let us_core_ethnicity = [
    r4us.UsCoreEthnicity(
      text: ethnicity_display,
      detailed: [],
      omb_category: Some(ethnicity),
    ),
  ]

  form.success(
    r4us.Patient(
      ..r4us.patient_new(),
      name: [r4us.Humanname(..r4us.humanname_new(), family:, given:)],
      birth_date: birth_date,
      telecom:,
      gender:,
      us_core_race:,
      us_core_ethnicity:,
      address:,
    ),
  )
}
