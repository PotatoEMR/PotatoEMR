package utils

import (
	"errors"
	"strconv"
	"time"

	r4 "github.com/PotatoEMR/simple-fhir-client/r4"
)

func GetPatientPhotoSrc(pat *r4.Patient) *string {
	if len(pat.Photo) != 0 {
		return GetPhotoSrc(&pat.Photo[0])
	}
	return nil
}

func GetPhotoSrc(photo *r4.Attachment) *string {
	if photo.Url != nil {
		return photo.Url
	} else if photo.Data != nil {
		dataSrc := "data:" + *photo.ContentType + ";base64," + *photo.Data
		return &dataSrc
	}
	return nil
}

func ObservationValueString(obs *r4.Observation) string {
	if obs.ValueQuantity != nil {
		if obs.ValueQuantity.Value != nil {
			if obs.ValueQuantity.Unit != nil {
				return strconv.FormatFloat(*obs.ValueQuantity.Value, 'f', 2, 64) + *obs.ValueQuantity.Unit
			}
			return strconv.FormatFloat(*obs.ValueQuantity.Value, 'f', 2, 64)
		}
	} else if obs.ValueCodeableConcept != nil {
		return obs.ValueCodeableConcept.String()
	} else if obs.ValueString != nil {
		return *obs.ValueString
	} else if obs.ValueBoolean != nil {
		return strconv.FormatBool(*obs.ValueBoolean)
	} else if obs.ValueRange != nil {
		//could put unit but whatever
		if obs.ValueRange.Low != nil && obs.ValueRange.High != nil {
			return strconv.FormatFloat(*obs.ValueRange.Low.Value, 'f', 2, 64) + "-" + strconv.FormatFloat(*obs.ValueRange.High.Value, 'f', 2, 64)
		} else if obs.ValueRange.Low != nil {
			return ">" + strconv.FormatFloat(*obs.ValueRange.Low.Value, 'f', 2, 64)
		} else if obs.ValueRange.High != nil {
			return "<" + strconv.FormatFloat(*obs.ValueRange.High.Value, 'f', 2, 64)
		} else {
			return ""
		}
	} else if obs.ValueRatio != nil {
		if obs.ValueRatio.Denominator != nil && obs.ValueRatio.Numerator != nil {
			if obs.ValueRatio.Denominator.Value != nil && obs.ValueRatio.Denominator != nil {
				return strconv.FormatFloat(*obs.ValueRatio.Numerator.Value, 'f', 2, 64) + "/" + strconv.FormatFloat(*obs.ValueRatio.Denominator.Value, 'f', 2, 64)
			}
		}
		return ""
	} else if obs.ValueSampledData != nil {
		return "sampled data idk"
	} else if obs.ValueTime != nil {
		return *obs.ValueTime
	} else if obs.ValueDateTime != nil {
		return (*obs.ValueDateTime).Format(r4.FhirDateTimeFormat)
	} else if obs.ValuePeriod != nil {
		return "period lazy"
	}
	return ""
}

func ObservationTime(obs *r4.Observation) (*string, error) {
	if obs.EffectiveDateTime != nil {
		ret := obs.EffectiveDateTime.Format(time.DateTime)
		return &ret, nil
	} else if obs.EffectiveInstant != nil {
		return obs.EffectiveInstant, nil
	} else if obs.EffectivePeriod != nil {
		return nil, errors.New("period lazy")
	} else if obs.EffectiveTiming != nil {
		return nil, errors.New("timing lazy")
	}
	return nil, errors.New("ObservationTime none of Observation.effective[x] populated, obs has no time")
}

func ParseHTMLDateTimeLocal(s string) (time.Time, error) {
	var t time.Time
	var err error
	for _, layout := range []string{"2006-01-02T15:04", "2006-01-02T15:04:05"} {
		t, err = time.Parse(layout, s)
		if err == nil {
			return t, nil
		}
	}
	return time.Time{}, err
}
