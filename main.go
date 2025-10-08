package main

import (
	"flag"
	"fmt"
	"net/http"

	"github.com/a-h/templ"

	pages "github.com/PotatoEMR/PotatoEMR/pages"
	pages_patient "github.com/PotatoEMR/PotatoEMR/pages/patient"
	"github.com/PotatoEMR/simple-fhir-client/r4Client"
)

func main() {
	port := flag.String("port", "8000", "will run potatoemr on 127.0.0.1:<port>")
	fhirServer := flag.String("fhirServer", "r4.smarthealthit.org/", "will run potatoemr on 127.0.0.1:<port>")
	flag.Parse()

	client := r4Client.New(*fhirServer)
	pages.Client = client
	pages_patient.Client = client

	//would like named urls, url params -> func, maybe sub routing
	mux := http.NewServeMux()

	fs := http.FileServer(http.Dir("static"))
	mux.Handle("GET /static/", http.StripPrefix("/static/", fs))

	mux.Handle("GET /", templ.Handler(pages.Index()))
	mux.HandleFunc("POST /searchPatient", pages.SearchPatient)

	mux.HandleFunc("GET /patient/{patId}/allergies/", pages_patient.Allergies)
	mux.HandleFunc("POST /patient/{patId}/allergies/create/", pages_patient.AllergiesCreate)
	mux.HandleFunc("POST /patient/{patId}/allergies/update/{allergyId}", pages_patient.AllergiesUpdate)
	mux.HandleFunc("POST /patient/{patId}/allergies/delete/{allergyId}", pages_patient.AllergiesDelete)

	mux.HandleFunc("GET /patient/{patId}/patientinfo/", pages_patient.PatientInfo)

	mux.HandleFunc("GET /patient/{patId}/immunizations/", pages_patient.Immunizations)
	mux.HandleFunc("POST /patient/{patId}/immunizations/create/", pages_patient.ImmunizationsCreate)
	mux.HandleFunc("POST /patient/{patId}/immunizations/update/{immId}", pages_patient.ImmunizationsUpdate)
	mux.HandleFunc("POST /patient/{patId}/immunizations/delete/{immId}", pages_patient.ImmunizationsDelete)

	mux.HandleFunc("GET /patient/{patId}/medications/", pages_patient.Medications)
	mux.HandleFunc("GET /patient/{patId}/overview/", pages_patient.Overview)

	mux.HandleFunc("GET /patient/{patId}/vitalsigns/", pages_patient.ObservationVitalSigns)
	mux.HandleFunc("POST /patient/{patId}/vitalsigns/create/", pages_patient.ObservationVitalSignsCreate)

	fmt.Println("🥔🥔🥔 PotatoEMR running on http://127.0.0.1:" + *port)
	http.ListenAndServe(":"+*port, mux)
}
