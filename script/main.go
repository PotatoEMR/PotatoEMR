package main

import (
	"encoding/json"
	"fmt"

	"github.com/PotatoEMR/simple-fhir-client/r4"
	"github.com/PotatoEMR/simple-fhir-client/r4Client"
)

func main() {
	client := r4Client.New("hapi.fhir.org/baseR4/")
	/*	givenName1 := "Robert"
		givenName2 := "Allen"
		familyName := "Zimmerman"
		pat := r4.Patient{Name: []r4.HumanName{{Family: &familyName, Given: []string{givenName1, givenName2}}}}
		createdPat, err1 := client.CreatePatient(&pat)
		patRef := createdPat.ToRef()
		ct := r4.CareTeam{Subject: &patRef}
		createdCt, err2 := client.CreateCareTeam(&ct)
		fmt.Println(err1, err2, *createdPat.Id, *createdCt.Id)*/
	ct, _ := client.ReadCareTeam("49335002")
	bundlePract, _ := client.SearchGrouped(r4Client.SpPractitioner{})
	for i, pract := range bundlePract.Practitioners {
		if i > 10 && i < 12 {
			fmt.Println(i)
			practRef := pract.ToRef()
			if practRef.Identifier != nil {
				practRef.Identifier.Assigner = nil
				//HAPI server has practitioner with "assigner":{"reference":"Organization?identifier=http://fhir.nlchi.nl.ca/organizationIdentifiers/NLCHI|TELUS"}
				//but then doesn't like that in careteam reference to practitioner
			}
			pr, _ := json.Marshal(practRef)
			fmt.Println(string(pr))
			part := r4.CareTeamParticipant{Member: &practRef}
			ct.Participant = append(ct.Participant, part)
		}
	}
	j, _ := json.Marshal(ct)
	fmt.Println(string(j))
	ct, err := client.UpdateCareTeam(ct)
	fmt.Println("err", err)
	j, _ = json.Marshal(ct)
	fmt.Println(string(j))
}
