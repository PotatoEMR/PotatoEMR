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
  PatientAllergies(FormState(r4us.Allergyintolerance))
  PatientMedications
  PatientVitals
  PatientPhotos
}

// similarly when update goes to these routes
// can easily set model.pat_id to None without duplication
pub type RouteNoId {
  Index
  Settings
  RegisterPatient(newpatient: Option(Form(r4us.Patient)))
  NotFound(notfound: String)
}

pub type FormState(a) {
  FormStateNone
  FormStateLoading
  FormStateSome(Form(a))
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
        PatientAllergies(_) -> "/patient/" <> id <> "/allergies"
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
    ["registerpatient"] -> RouteNoId(RegisterPatient(None))
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
            page: PatientAllergies(FormStateNone),
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
  UserSubmittedAllergyForm(
    Result(r4us.Allergyintolerance, Form(r4us.Allergyintolerance)),
  )
  UserClickedCreateAllergy
  UserClickedEditAllergy(String)
  ServerUpdatedPatientPhoto(Result(r4us.Patient, r4us_rsvp.Err))
  UserSelectedPhotoEvent(dynamic.Dynamic)
  UserSelectedPhotoDataUrl(String)
  UserDraggingPhoto(Bool)
  UserClickedExistingPhoto(Int)
  UserClickedRegisterPatient(Result(r4us.Patient, Form(r4us.Patient)))
  ServerReturnedRegisterPatient(Result(r4us.Patient, r4us_rsvp.Err))
}
