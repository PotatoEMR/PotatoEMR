package main

import (
	"flag"
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/PotatoEMR/simple-fhir-client/r4Client"
)

// mux with method to return url string for templates to use
// so we don't have to hardcode <a href="/patient/" + *pat.Id + "/overview">
type NamedServeMux struct {
	*http.ServeMux
}

// add handlefunc to mux like normal,
// but also return a url string to use in templates
func (m *NamedServeMux) namedHandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request)) string {
	m.HandleFunc(pattern, handler)

	parts := strings.SplitN(pattern, " ", 2)
	path := pattern
	if len(parts) == 2 {
		//remove the GET or POST or whatever if space at beginning of "GET /patient/{patId}/allergies/"
		path = parts[1]
	}
	re := regexp.MustCompile(`\{[^/}]+\}`)
	//replace {patId} or {whatever} with %s for fmt.Sprintf to use
	format := re.ReplaceAllString(path, "%s")
	return format
}

// template url strings declared here and set by namedHandleFunc later to prevent cycle
// kind of annoying to do all this and repeat all the urls
// but definitely dont want manual urls in templates
var get_index, post_index, post_searchPatient, get_registerPatient, post_registerPatient, get_calendar, get_patientLists, get_settings string
var get_patient_allergies, post_patient_allergiesCreate, post_patient_allergiesUpdate, post_patient_allergiesDelete string
var get_patient, get_patient_overview string
var get_patient_info string
var get_patient_immunizations, post_patient_immunizationsCreate, post_patient_immunizationsUpdate, post_patient_immunizationsDelete string
var get_patient_medications string
var get_patient_observationVitalSigns, post_patient_observationVitalSigns string

var client *r4Client.FhirClient

func main() {
	port := flag.String("port", "8000", "will run potatoemr on 127.0.0.1:<port>")
	fhirServer := flag.String("fhirServer", "r4.smarthealthit.org/", "will run potatoemr on 127.0.0.1:<port>")
	flag.Parse()

	client = r4Client.New(*fhirServer)

	mux := &NamedServeMux{http.NewServeMux()}

	fs := http.FileServer(http.Dir("static"))
	mux.Handle("GET /static/", http.StripPrefix("/static/", fs))

	get_index = mux.namedHandleFunc("GET /", my_Index)
	post_index = mux.namedHandleFunc("POST /", my_Index) //not a real post url but in case we type wrong url in form post
	post_searchPatient = mux.namedHandleFunc("POST /searchpatient", my_SearchPatient)
	get_registerPatient = mux.namedHandleFunc("GET /registerpatient", my_RegisterPatient)
	post_registerPatient = mux.namedHandleFunc("POST /registerpatient", my_RegisterPatientCreate)
	get_calendar = mux.namedHandleFunc("GET /calendar", my_Calendar)
	get_patientLists = mux.namedHandleFunc("GET /patientlists", my_PatientLists)
	get_settings = mux.namedHandleFunc("GET /settings", my_Settings)

	get_patient_allergies = mux.namedHandleFunc("GET /patient/{patId}/allergies/", patient_Allergies)
	post_patient_allergiesCreate = mux.namedHandleFunc("POST /patient/{patId}/allergies/create/", patient_AllergiesCreate)
	post_patient_allergiesUpdate = mux.namedHandleFunc("POST /patient/{patId}/allergies/update/{allergyId}", patient_AllergiesUpdate)
	post_patient_allergiesDelete = mux.namedHandleFunc("POST /patient/{patId}/allergies/delete/{allergyId}", patient_AllergiesDelete)

	get_patient = mux.namedHandleFunc("GET /patient/{patId}/", patient_Overview)
	get_patient_overview = mux.namedHandleFunc("GET /patient/{patId}/overview/", patient_Overview)

	get_patient_info = mux.namedHandleFunc("GET /patient/{patId}/patientinfo/", patient_PatientInfo)

	get_patient_immunizations = mux.namedHandleFunc("GET /patient/{patId}/immunizations/", patient_Immunizations)
	post_patient_immunizationsCreate = mux.namedHandleFunc("POST /patient/{patId}/immunizations/create/", patient_ImmunizationsCreate)
	post_patient_immunizationsUpdate = mux.namedHandleFunc("POST /patient/{patId}/immunizations/update/{immId}", patient_ImmunizationsUpdate)
	post_patient_immunizationsDelete = mux.namedHandleFunc("POST /patient/{patId}/immunizations/delete/{immId}", patient_ImmunizationsDelete)

	get_patient_medications = mux.namedHandleFunc("GET /patient/{patId}/medications/", patient_Medications)

	get_patient_observationVitalSigns = mux.namedHandleFunc("GET /patient/{patId}/vitalsigns/", patient_ObservationVitalSigns)
	post_patient_observationVitalSigns = mux.namedHandleFunc("POST /patient/{patId}/vitalsigns/create/", patient_ObservationVitalSignsCreate)

	fmt.Println("🥔🥔🥔 PotatoEMR running on http://127.0.0.1:" + *port)
	http.ListenAndServe(":"+*port, mux)
}
