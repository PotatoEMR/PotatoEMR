import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_sansio
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/dict
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
    patient_documentreferences: List(r4us.Documentreference),
    patient_encounters: List(r4us.Encounter),
    patient_immunizations: List(r4us.Immunization),
    patient_medications: List(r4us.Medication),
    patient_medication_requests: List(r4us.Medicationrequest),
    patient_medication_statements: List(r4us.Medicationstatement),
    patient_observations: List(r4us.Observation),
  )
}

pub type EncounterNote {
  EncounterNote(
    encounter: r4us.Encounter,
    note: Option(r4us.Documentreference),
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
  PatientDemographics(FormState(r4us.Patient))
  PatientAllergies(FormState(r4us.Allergyintolerance))
  PatientEncounters(FormState(EncounterNote))
  PatientImmunizations(FormState(r4us.Immunization))
  PatientMedications(FormState(r4us.Medicationstatement))
  PatientOrders(FormState(r4us.Medicationrequest))
  PatientVitals(FormState(List(r4us.Observation)))
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
    RoutePatient(_patient, id:, page:) -> {
      let ending = case page {
        PatientOverview -> "overview"
        PatientDemographics(_) -> "demographics"
        PatientAllergies(_) -> "allergies"
        PatientEncounters(_) -> "encounters"
        PatientMedications(_) -> "medications"
        PatientOrders(_) -> "orders"
        PatientVitals(_) -> "vitals"
        PatientPhotos -> "photos"
        PatientImmunizations(_) -> "immunizations"
      }
      "/patient/" <> id <> "/" <> ending
    }
  }
}

pub const pages_no_id: List(#(String, RouteNoId)) = [
  #("home", Index),
  #("settings", Settings),
  #("registerpatient", RegisterPatient(None)),
]

pub const pages_patient: List(#(String, RoutePatientPage)) = [
  #("overview", PatientOverview),
  #("demographics", PatientDemographics(FormStateNone)),
  #("allergies", PatientAllergies(FormStateNone)),
  #("encounters", PatientEncounters(FormStateNone)),
  #("immunizations", PatientImmunizations(FormStateNone)),
  #("medications", PatientMedications(FormStateNone)),
  #("orders", PatientOrders(FormStateNone)),
  #("vitals", PatientVitals(FormStateNone)),
  #("photos", PatientPhotos),
]

pub fn uri_to_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] -> RouteNoId(Index)
    [""] -> RouteNoId(Index)
    [page] ->
      case pages_no_id |> dict.from_list |> dict.get(page) {
        Ok(page) -> RouteNoId(page:)
        Error(_) -> uri |> uri.to_string |> NotFound |> RouteNoId
      }
    ["patient", id, page] ->
      case pages_patient |> dict.from_list |> dict.get(page) {
        Ok(page) -> RoutePatient(id:, patient: PatientLoadStillLoading, page:)
        Error(_) -> uri |> uri.to_string |> NotFound |> RouteNoId
      }
    _ -> uri |> uri.to_string |> NotFound |> RouteNoId
  }
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  UserNavigatedTo(route: Route)
  ServerReturnedPatientEverything(Result(r4us.Bundle, r4us_rsvp.Err))
  UserFocusedSearch
  UserBlurredSearch
  UserSearchedPatient(String)
  ServerReturnedSearchPatients(Result(List(r4us.Patient), r4us_rsvp.Err))
  MsgDemographics(SubmsgDemographics)
  MsgAllergy(SubmsgAllergy)
  MsgEncounter(SubmsgEncounter)
  MsgImmunization(SubmsgImmunization)
  MsgMedication(SubmsgMedication)
  MsgOrder(SubmsgOrder)
  MsgVitals(SubmsgVitals)
  MsgPhoto(SubmsgPhoto)
  MsgRegisterPatient(SubmsgRegisterPatient)
  MsgSettings(SubmsgSettings)
}

pub type SubmsgSettings {
  UserClickedChangeClient(String)
}

pub type SubmsgRegisterPatient {
  UserClickedRegisterPatient(Result(r4us.Patient, Form(r4us.Patient)))
  UserClickedAddRegisterPatientName(List(#(String, String)))
  UserClickedDeleteRegisterPatientName(List(#(String, String)))
  UserClickedAddRegisterPatientRecordedGender(List(#(String, String)))
  UserClickedDeleteRegisterPatientRecordedGender(List(#(String, String)))
  UserClickedAddRegisterPatientIdentifier(List(#(String, String)))
  UserClickedDeleteRegisterPatientIdentifier(List(#(String, String)))
  ServerReturnedRegisterPatient(Result(r4us.Patient, r4us_rsvp.Err))
}

pub type SubmsgPhoto {
  ServerUpdatedPatientPhoto(Result(r4us.Patient, r4us_rsvp.Err))
  UserSelectedPhotoEvent(dynamic.Dynamic)
  UserSelectedPhotoDataUrl(String)
  UserDraggingPhoto(Bool)
  UserClickedExistingPhoto(Int)
}

pub type SubmsgDemographics {
  ServerUpdatedPatientDemographics(Result(r4us.Patient, r4us_rsvp.Err))
  UserClickedEditDemographics
  UserClickedCloseDemographicsForm
  UserClickedAddDemographicsName(List(#(String, String)))
  UserClickedDeleteDemographicsName(List(#(String, String)))
  UserClickedAddDemographicsRecordedGender(List(#(String, String)))
  UserClickedDeleteDemographicsRecordedGender(List(#(String, String)))
  UserClickedAddDemographicsIdentifier(List(#(String, String)))
  UserClickedDeleteDemographicsIdentifier(List(#(String, String)))
  UserSubmittedDemographicsForm(Result(r4us.Patient, Form(r4us.Patient)))
}

pub type SubmsgAllergy {
  ServerCreatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerUpdatedAllergy(Result(r4us.Allergyintolerance, r4us_rsvp.Err))
  ServerDeletedAllergy(
    Result(r4us_sansio.OperationoutcomeOrHTTP, r4us_rsvp.Err),
  )
  UserSubmittedAllergyForm(
    Result(r4us.Allergyintolerance, Form(r4us.Allergyintolerance)),
  )
  UserClickedCreateAllergy
  UserClickedEditAllergy(String)
  UserClickedDeleteAllergy(String)
  UserClickedCloseAllergyForm
}

pub type SubmsgVitals {
  UserClickedCreateVitals
  UserClickedEditVitalsColumn(String)
  UserClickedDeleteVitalsColumn(String)
  UserClickedCloseVitalsForm
  UserSubmittedVitalsForm(
    Result(List(r4us.Observation), Form(List(r4us.Observation))),
  )
  ServerReturnedVitalsBundle(Result(r4us.Bundle, r4us_rsvp.Err))
  ServerReturnedVitalsDelete(String, Result(r4us.Bundle, r4us_rsvp.Err))
}

pub type SubmsgMedication {
  ServerCreatedMedication(Result(r4us.Medicationstatement, r4us_rsvp.Err))
  ServerUpdatedMedication(Result(r4us.Medicationstatement, r4us_rsvp.Err))
  ServerDeletedMedication(
    Result(r4us_sansio.OperationoutcomeOrHTTP, r4us_rsvp.Err),
  )
  UserSubmittedMedicationForm(
    Result(r4us.Medicationstatement, Form(r4us.Medicationstatement)),
  )
  UserClickedCreateMedication
  UserClickedEditMedication(String)
  UserClickedDeleteMedication(String)
  UserClickedCloseMedicationForm
}

pub type SubmsgOrder {
  ServerCreatedOrder(Result(r4us.Medicationrequest, r4us_rsvp.Err))
  ServerUpdatedOrder(Result(r4us.Medicationrequest, r4us_rsvp.Err))
  ServerDeletedOrder(Result(r4us_sansio.OperationoutcomeOrHTTP, r4us_rsvp.Err))
  UserSubmittedOrderForm(
    Result(r4us.Medicationrequest, Form(r4us.Medicationrequest)),
  )
  UserClickedCreateOrder
  UserClickedEditOrder(String)
  UserClickedDeleteOrder(String)
  UserClickedCloseOrderForm
}

pub type SubmsgEncounter {
  ServerCreatedEncounter(
    Result(r4us.Encounter, r4us_rsvp.Err),
    Option(r4us.Documentreference),
  )
  ServerUpdatedEncounter(
    Result(r4us.Encounter, r4us_rsvp.Err),
    Option(r4us.Documentreference),
  )
  ServerSavedEncounterNote(Result(r4us.Documentreference, r4us_rsvp.Err))
  ServerDeletedEncounterNote(
    Result(r4us_sansio.OperationoutcomeOrHTTP, r4us_rsvp.Err),
  )
  ServerDeletedEncounter(
    Result(r4us_sansio.OperationoutcomeOrHTTP, r4us_rsvp.Err),
  )
  UserSubmittedEncounterForm(Result(EncounterNote, Form(EncounterNote)))
  UserClickedCreateEncounter
  UserClickedEditEncounter(String)
  UserClickedDeleteEncounter(String)
  UserClickedCloseEncounterForm
}

pub type SubmsgImmunization {
  ServerCreatedImmunization(Result(r4us.Immunization, r4us_rsvp.Err))
  ServerUpdatedImmunization(Result(r4us.Immunization, r4us_rsvp.Err))
  ServerDeletedImmunization(
    Result(r4us_sansio.OperationoutcomeOrHTTP, r4us_rsvp.Err),
  )
  UserSubmittedImmunizationForm(
    Result(r4us.Immunization, Form(r4us.Immunization)),
  )
  UserClickedCreateImmunization
  UserClickedEditImmunization(String)
  UserClickedDeleteImmunization(String)
  UserClickedCloseImmunizationForm
}
