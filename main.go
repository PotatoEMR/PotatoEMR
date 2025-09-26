package main

import (
	"fmt"
	"net/http"

	"github.com/a-h/templ"

	pages "github.com/PotatoEMR/PotatoEMR/pages"
	pages_patient "github.com/PotatoEMR/PotatoEMR/pages/patient"
	"github.com/PotatoEMR/simple-fhir-client/r4Client"
)

func main() {
	client := r4Client.New("r4.smarthealthit.org/")
	// client := r4Client.New("hapi.fhir.org/baseR4/")
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

	mux.HandleFunc("GET /patient/{patId}/demographics/", pages_patient.Demographics)
	mux.HandleFunc("GET /patient/{patId}/immunizations/", pages_patient.Immunizations)
	mux.HandleFunc("GET /patient/{patId}/medications/", pages_patient.Medications)
	mux.HandleFunc("GET /patient/{patId}/overview/", pages_patient.Overview)

	mux.HandleFunc("GET /patient/{patId}/vitalsigns/", pages_patient.ObservationVitalSigns)
	mux.HandleFunc("POST /patient/{patId}/vitalsigns/create/", pages_patient.ObservationVitalSignsCreate)

	fmt.Println("running on http://127.0.0.1:8000/")
	http.ListenAndServe(":8000", mux)
}
