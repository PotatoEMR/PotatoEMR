pub const system = "http://terminology.hl7.org/CodeSystem/v3-ActCode"

pub const v3_actencountercode: List(#(String, String)) = [
  #("AMB", "ambulatory"),
  #("EMER", "emergency"),
  #("FLD", "field"),
  #("HH", "home health"),
  #("IMP", "inpatient encounter"),
  #("ACUTE", "inpatient acute"),
  #("NONAC", "inpatient non-acute"),
  #("OBSENC", "observation encounter"),
  #("PRENC", "pre-admission"),
  #("SS", "short stay"),
  #("VR", "virtual"),
]
