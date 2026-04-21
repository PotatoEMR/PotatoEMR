// This extension is deprecated and should no longer be used
// This extension is no longer a USCDI requirement and is deprecated.
// It SHOULD NOT be used for new or revised content.
// It is retained for historical/backward compatibility purposes.
// Implementers can use the HL7 standard extension instead
//
// maybe having mtf and ftm as codes was counterproductive
// here is a confluence link that links to a paywalled journal article
// https://confluence.hl7.org/spaces/VOC/pages/90351184/Gender+Harmony

pub const codes: List(#(String, String, String)) = [
  #("33791000087105", "http://snomed.info/sct", "nonbinary"),
  #("407376001", "http://snomed.info/sct", "male to female"),
  #("407377005", "http://snomed.info/sct", "female to male"),
  #("446141000124107", "http://snomed.info/sct", "female"),
  #("446151000124109", "http://snomed.info/sct", "male"),
  #("OTH", "http://terminology.hl7.org/CodeSystem/v3-NullFlavor", "other"),
  #("UNK", "http://terminology.hl7.org/CodeSystem/v3-NullFlavor", "unknown"),
  #(
    "asked-declined",
    "http://terminology.hl7.org/CodeSystem/data-absent-reason",
    "Asked But Declined",
  ),
]
