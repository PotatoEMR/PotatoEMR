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

// thought it would help to convert extensions to url->extension map
// but would need to convert back and forth with existing extension array since they have different json marhsal
// idk maybe but probably easier to stick with extension array
// in terms of time complexity there's probably a better map solution but for now not bothering

// // normally a resource has an array of extensions, each with a url
// // extensions also themselves have array of extensions
// // we might want to get an extension by url
// // eg myExt["http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity"]
// // so ExtensionUrlMap, in addition to []Extension, has map[string]ExtensionUrlMap
// // because extensions can themselves have extensions it's recursive, so you only have to call once
// //
// // usage:
// //
// //	patExtMap := utils.ExtensionUrlMap{}
// //	patExtMap.FromExtensionList(myPatient.Extension)
// type ExtensionUrlMap struct {
// 	r4.Extension
// 	ExtUrlMaps map[string]ExtensionUrlMap
// }

// // converts list of extensions to map of url -> extension
// // eg patExtMap.FromExtensionList(myPatient.Extension)
// func (e *ExtensionUrlMap) FromExtensionList(exts []r4.Extension) {
// 	extUrlMap := make(map[string]ExtensionUrlMap)
// 	for _, ext := range exts {
// 		childExtUrlMap := ExtensionUrlMap{
// 			Extension: ext,
// 		}
// 		childExtUrlMap.FromExtensionList(ext.Extension)
// 		extUrlMap[ext.Url] = childExtUrlMap
// 	}
// 	e.ExtUrlMaps = extUrlMap
// }

// // converts back to list of extensions from url -> extension map
// func (e *ExtensionUrlMap) ToExtensionList() []r4.Extension {
// 	var exts []r4.Extension
// 	for _, child := range e.ExtUrlMaps {
// 		childExt := child.Extension
// 		childExt.Extension = child.ToExtensionList()
// 		exts = append(exts, childExt)
// 	}
// 	return exts
// }

// // patExtMap.ExtUrlMaps["http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity"].ExtUrlMaps["ombCategory"] equivalent
// // but takes nil receiver so can be chained
// //
// // patExtMap.GetUrlExt("http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity").GetUrlExt("ombCategory")
// // so if any are nil it will return nil in the end, instead of crashing midway
// func (e *ExtensionUrlMap) GetUrlExt(url string) *ExtensionUrlMap {
// 	if e == nil {
// 		return nil
// 	}
// 	if url_ExtUrlMap, ok := e.ExtUrlMaps[url]; ok {
// 		return &url_ExtUrlMap
// 	}
// 	return nil
// }

// package r4

// import (
// 	"strings"

// 	"github.com/a-h/templ"
// )

// //generated with command go run ./bultaoreune
// //inputs https://www.hl7.org/fhir/r4/[profiles-resources.json profiles-types.json valuesets.json]
// //for details see https://github.com/PotatoEMR/simple-fhir-client

// // http://hl7.org/fhir/r4/StructureDefinition/Extension
// type Extension struct {
// 	Id                       *string              `json:"id,omitempty"`
// 	Extension                []Extension          `json:"extension,omitempty"`
// 	Url                      string               `json:"url"`
// 	ValueBase64Binary        *string              `json:"valueBase64Binary,omitempty"`
// 	ValueBoolean             *bool                `json:"valueBoolean,omitempty"`
// 	ValueCanonical           *string              `json:"valueCanonical,omitempty"`
// 	ValueCode                *string              `json:"valueCode,omitempty"`
// 	ValueDate                *FhirDate            `json:"valueDate,omitempty"`
// 	ValueDateTime            *FhirDateTime        `json:"valueDateTime,omitempty"`
// 	ValueDecimal             *float64             `json:"valueDecimal,omitempty"`
// 	ValueId                  *string              `json:"valueId,omitempty"`
// 	ValueInstant             *string              `json:"valueInstant,omitempty"`
// 	ValueInteger             *int                 `json:"valueInteger,omitempty"`
// 	ValueMarkdown            *string              `json:"valueMarkdown,omitempty"`
// 	ValueOid                 *string              `json:"valueOid,omitempty"`
// 	ValuePositiveInt         *int                 `json:"valuePositiveInt,omitempty"`
// 	ValueString              *string              `json:"valueString,omitempty"`
// 	ValueTime                *string              `json:"valueTime,omitempty"`
// 	ValueUnsignedInt         *int                 `json:"valueUnsignedInt,omitempty"`
// 	ValueUri                 *string              `json:"valueUri,omitempty"`
// 	ValueUrl                 *string              `json:"valueUrl,omitempty"`
// 	ValueUuid                *string              `json:"valueUuid,omitempty"`
// 	ValueAddress             *Address             `json:"valueAddress,omitempty"`
// 	ValueAge                 *Age                 `json:"valueAge,omitempty"`
// 	ValueAnnotation          *Annotation          `json:"valueAnnotation,omitempty"`
// 	ValueAttachment          *Attachment          `json:"valueAttachment,omitempty"`
// 	ValueCodeableConcept     *CodeableConcept     `json:"valueCodeableConcept,omitempty"`
// 	ValueCoding              *Coding              `json:"valueCoding,omitempty"`
// 	ValueContactPoint        *ContactPoint        `json:"valueContactPoint,omitempty"`
// 	ValueCount               *Count               `json:"valueCount,omitempty"`
// 	ValueDistance            *Distance            `json:"valueDistance,omitempty"`
// 	ValueDuration            *Duration            `json:"valueDuration,omitempty"`
// 	ValueHumanName           *HumanName           `json:"valueHumanName,omitempty"`
// 	ValueIdentifier          *Identifier          `json:"valueIdentifier,omitempty"`
// 	ValueMoney               *Money               `json:"valueMoney,omitempty"`
// 	ValuePeriod              *Period              `json:"valuePeriod,omitempty"`
// 	ValueQuantity            *Quantity            `json:"valueQuantity,omitempty"`
// 	ValueRange               *Range               `json:"valueRange,omitempty"`
// 	ValueRatio               *Ratio               `json:"valueRatio,omitempty"`
// 	ValueReference           *Reference           `json:"valueReference,omitempty"`
// 	ValueSampledData         *SampledData         `json:"valueSampledData,omitempty"`
// 	ValueSignature           *Signature           `json:"valueSignature,omitempty"`
// 	ValueTiming              *Timing              `json:"valueTiming,omitempty"`
// 	ValueContactDetail       *ContactDetail       `json:"valueContactDetail,omitempty"`
// 	ValueContributor         *Contributor         `json:"valueContributor,omitempty"`
// 	ValueDataRequirement     *DataRequirement     `json:"valueDataRequirement,omitempty"`
// 	ValueExpression          *Expression          `json:"valueExpression,omitempty"`
// 	ValueParameterDefinition *ParameterDefinition `json:"valueParameterDefinition,omitempty"`
// 	ValueRelatedArtifact     *RelatedArtifact     `json:"valueRelatedArtifact,omitempty"`
// 	ValueTriggerDefinition   *TriggerDefinition   `json:"valueTriggerDefinition,omitempty"`
// 	ValueUsageContext        *UsageContext        `json:"valueUsageContext,omitempty"`
// 	ValueDosage              *Dosage              `json:"valueDosage,omitempty"`
// 	ValueMeta                *Meta                `json:"valueMeta,omitempty"`
// }

// func GetExtByUrl(getFrom []Extension, url string) *Extension {
// 	if url == "" {
// 		return nil
// 	}
// 	for _, ext := range getFrom {
// 		if ext.Url == url {
// 			return &ext
// 		}
// 	}
// 	return nil
// }

// func (e *Extension) ExtList_GetExtByUrl(url string) *Extension {
// 	return GetExtByUrl(e.Extension, url)
// }

// func GetExtByUrl_List(getFrom []Extension, urls []string) *Extension {
// 	currentList := getFrom
// 	var currentExt *Extension
// 	for _, url := range urls {
// 		currentExt = GetExtByUrl(currentList, url)
// 		if currentList == nil {
// 			return nil
// 		}
// 		currentList = currentExt.Extension
// 	}
// 	return currentExt
// }

// func SetExtByUrl(url string, ext Extension, setIn []Extension) []Extension {
// 	if url == "" {
// 		return setIn
// 	}
// 	for i := range setIn {
// 		if setIn[i].Url == url {
// 			setIn[i] = ext
// 			return setIn
// 		}
// 	}
// 	return append(setIn, ext)
// }

// func inputNameFromUrls(urls []string) string {
// 	wrapped := make([]string, len(urls))
// 	for i, url := range urls {
// 		wrapped[i] = "extension[" + url + "]"
// 	}
// 	return strings.Join(wrapped, ".")
// }

// func T_ExtCoding(htmlAttrs templ.Attributes, vs []Coding, getFrom []Extension, urls []string) templ.Component {
// 	ext := GetExtByUrl_List(getFrom, urls)
// 	return CodingSelect(inputNameFromUrls(urls), ext.ValueCoding, vs, htmlAttrs)
// }
// func T_ExtString(htmlAttrs templ.Attributes, getFrom []Extension, urls []string) templ.Component {
// 	ext := GetExtByUrl_List(getFrom, urls)
// 	return StringInput(inputNameFromUrls(urls), ext.ValueString, htmlAttrs)
// }
