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

var mux = &NamedServeMux{http.NewServeMux()}

var get_index = mux.namedHandleFunc("GET /", my_Index)
var post_index = mux.namedHandleFunc("POST /", my_Index) //not a real post url but in case we type wrong url in form post
var post_searchPatient = mux.namedHandleFunc("POST /searchpatient", my_SearchPatient)
var get_registerPatient = mux.namedHandleFunc("GET /registerpatient", my_RegisterPatient)
var post_registerPatient = mux.namedHandleFunc("POST /registerpatient", my_RegisterPatientCreate)
var get_calendar = mux.namedHandleFunc("GET /calendar", my_Calendar)
var get_patientLists = mux.namedHandleFunc("GET /patientlists", my_PatientLists)
var get_settings = mux.namedHandleFunc("GET /settings", my_Settings)

var get_patient_allergies = mux.namedHandleFunc("GET /patient/{patId}/allergies/", patient_Allergies)
var post_patient_allergiesCreate = mux.namedHandleFunc("POST /patient/{patId}/allergies/create/", patient_AllergiesCreate)
var post_patient_allergiesUpdate = mux.namedHandleFunc("POST /patient/{patId}/allergies/update/{allergyId}", patient_AllergiesUpdate)
var post_patient_allergiesDelete = mux.namedHandleFunc("POST /patient/{patId}/allergies/delete/{allergyId}", patient_AllergiesDelete)

var get_patient = mux.namedHandleFunc("GET /patient/{patId}/", patient_Overview)
var get_patient_overview = mux.namedHandleFunc("GET /patient/{patId}/overview/", patient_Overview)

var get_patient_info = mux.namedHandleFunc("GET /patient/{patId}/patientinfo/", patient_PatientInfo)

var get_patient_immunizations = mux.namedHandleFunc("GET /patient/{patId}/immunizations/", patient_Immunizations)
var post_patient_immunizationsCreate = mux.namedHandleFunc("POST /patient/{patId}/immunizations/create/", patient_ImmunizationsCreate)
var post_patient_immunizationsUpdate = mux.namedHandleFunc("POST /patient/{patId}/immunizations/update/{immId}", patient_ImmunizationsUpdate)
var post_patient_immunizationsDelete = mux.namedHandleFunc("POST /patient/{patId}/immunizations/delete/{immId}", patient_ImmunizationsDelete)

var get_patient_medications = mux.namedHandleFunc("GET /patient/{patId}/medications/", patient_Medications)

var get_patient_observationVitalSigns = mux.namedHandleFunc("GET /patient/{patId}/vitalsigns/", patient_ObservationVitalSigns)
var post_patient_observationVitalSigns = mux.namedHandleFunc("POST /patient/{patId}/vitalsigns/create/", patient_ObservationVitalSignsCreate)

var client *r4Client.FhirClient

func main() {
	port := flag.String("port", "8000", "will run potatoemr on 127.0.0.1:<port>")
	fhirServer := flag.String("fhirServer", "r4.smarthealthit.org/", "will run potatoemr on 127.0.0.1:<port>")
	flag.Parse()

	client = r4Client.New(*fhirServer)

	fs := http.FileServer(http.Dir("static"))
	mux.Handle("GET /static/", http.StripPrefix("/static/", fs))

	fmt.Println("🥔🥔🥔 PotatoEMR running on http://127.0.0.1:" + *port)
	http.ListenAndServe(":"+*port, mux)
}
