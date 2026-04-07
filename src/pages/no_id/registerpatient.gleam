import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre/attribute as a
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import modem
import utils

pub fn create(model: Model, newpat: r4us.Patient) {
  let effect =
    r4us_rsvp.patient_create(
      newpat,
      model.client,
      mm.ServerReturnedRegisterPatient,
    )
  #(model, effect)
}

pub fn form_errors(model: Model, err: Form(r4us.Patient)) {
  #(model, effect.none())
}

pub fn created(model: Model, created_pat: r4us.Patient) {
  case created_pat.id {
    None -> panic as "created no id?"
    Some(id) -> {
      let pat_url =
        mm.route_to_urlstring(mm.RoutePatient(
          id,
          mm.PatientLoadStillLoading,
          mm.PatientOverview,
        ))
        |> modem.push(None, None)
      #(model, pat_url)
    }
  }
}

pub fn create_error(model: Model, err) {
  echo "err on server"
  echo err
  #(model, effect.none())
}

pub fn view(newpatient: Option(Form(r4us.Patient))) {
  let newpatient = case newpatient {
    None -> form.new(patient_schema())
    Some(newpatient) -> newpatient
  }
  [
    h.form(
      [
        a.class("flex flex-row flex-wrap gap-2"),
        // The message provided to the built-in `on_submit` handler receives the
        // `FormData` associated with the form as a List of (name, value) tuples.
        //
        // The event handler also calls `preventDefault()` on the form, such that
        // Lustre can handle the submission instead off being sent off to the server.
        event.on_submit(fn(values) {
          newpatient
          |> form.add_values(values)
          |> form.run
          |> mm.UserClickedRegisterPatient
        }),
      ],
      [
        h.h1([a.class("text-2xl")], [
          h.text("Register Patient"),
        ]),
        //
        view_form_input(newpatient, is: "text", name: "first", label: "first"),
        view_form_input(newpatient, is: "text", name: "last", label: "last"),
        view_form_input(newpatient, is: "tel", name: "phone", label: "phone"),
        view_form_input(newpatient, is: "email", name: "email", label: "email"),
        view_form_select(
          newpatient,
          name: "gender",
          options: list.map(
            [
              r4us_valuesets.AdministrativegenderMale,
              r4us_valuesets.AdministrativegenderFemale,
              r4us_valuesets.AdministrativegenderOther,
              r4us_valuesets.AdministrativegenderUnknown,
            ],
            r4us_valuesets.administrativegender_to_string,
          ),
          label: "gender",
        ),
        view_form_select(
          newpatient,
          name: "race",
          options: [
            "American Indian or Alaska Native",
            "Asian",
            "Black or African American",
            "Native Hawaiian or Other Pacific Islander",
            "White",
          ],
          label: "race",
        ),
        view_form_select(
          newpatient,
          name: "ethnicity",
          options: [
            "Hispanic or Latino",
            "Not Hispanic or Latino",
          ],
          label: "ethnicity",
        ),
        view_form_input(
          newpatient,
          is: "text",
          name: "address_line",
          label: "address",
        ),
        view_form_input(
          newpatient,
          is: "text",
          name: "address_city",
          label: "city",
        ),
        view_form_input(
          newpatient,
          is: "text",
          name: "address_state",
          label: "state",
        ),
        view_form_input(
          newpatient,
          is: "text",
          name: "address_postal_code",
          label: "zip",
        ),
        //
        h.div([a.class("flex justify-end")], [
          h.button(
            [
              // buttons inside of forms submit the form by default.
              a.class("text-white text-sm font-bold"),
              a.class("px-4 py-2 bg-purple-600 rounded-lg"),
              a.class("hover:bg-purple-800"),
              a.class(
                "focus:outline-2 focus:outline-offset-2 focus:outline-purple-800",
              ),
            ],
            [h.text("Submit")],
          ),
        ]),
      ],
    ),
  ]
}

fn view_form_select(
  form: Form(a),
  name name: String,
  options options: List(String),
  label label: String,
) {
  let errors = form.field_error_messages(form, name)

  h.div([], [
    h.label([a.for(name), a.class("text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.select(
      [
        a.class("border border-slate-700 bg-slate-950"),
        case errors {
          [] -> a.class("focus:outline focus:outline-purple-600")
          _ -> a.class("outline outline-red-500")
        },
        // we use the `id` in the associated `for` a on the label.
        a.id(name),
        // the `name` attribute is used as the first element of the tuple
        // we receive for this input.
        a.name(name),
      ],
      list.map(options, fn(option) {
        h.option(
          [
            a.value(option),
          ],
          option,
        )
      }),
    ),
    // formal provides us with customisable error messages for every element
    // in case its validation fails, which we can show right below the input.
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

fn view_form_input(
  form: Form(a),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  h.div([], [
    h.label([a.for(name), a.class("text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.input([
      a.type_(type_),
      a.class("border border-slate-700 bg-slate-950"),
      case errors {
        [] -> a.class("focus:outline focus:outline-purple-600")
        _ -> a.class("outline outline-red-500")
      },
      // we use the `id` in the associated `for` a on the label.
      a.id(name),
      // the `name` attribute is used as the first element of the tuple
      // we receive for this input.
      a.name(name),
    ]),
    // formal provides us with customisable error messages for every element
    // in case its validation fails, which we can show right below the input.
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

pub fn patient_schema() {
  use given <- form.field("first", form.parse_string)
  let given = case given {
    "" -> []
    _ -> [given]
  }
  use family <- form.field("last", form.parse_optional(form.parse_string))
  use birth_date <- form.field(
    "birthdate",
    form.parse_optional(form.parse_string),
  )
  use phone <- form.field("phone", form.parse_string)
  let telecom = case phone {
    "" -> []
    _ -> [
      r4us.Contactpoint(
        ..r4us.contactpoint_new(),
        system: Some(r4us_valuesets.ContactpointsystemPhone),
        value: Some(phone),
      ),
    ]
  }
  use email <- form.field("email", form.parse_string)
  let telecom = case email {
    "" -> telecom
    _ -> [
      r4us.Contactpoint(
        ..r4us.contactpoint_new(),
        system: Some(r4us_valuesets.ContactpointsystemEmail),
        value: Some(email),
      ),
      ..telecom
    ]
  }
  use gender <- form.field("gender", form.parse_string)
  let gender = case r4us_valuesets.administrativegender_from_string(gender) {
    Ok(gender) -> Some(gender)
    Error(_) -> None
  }
  use race_display <- form.field("race", form.parse_string)
  let race = case race_display {
    "American Indian or Alaska Native" ->
      utils.coding(
        code: "1002-5",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "American Indian or Alaska Native",
      )
    "Asian" ->
      utils.coding(
        code: "2028-9",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Asian",
      )
    "Black or African American" ->
      utils.coding(
        code: "2054-5",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Black or African American",
      )
    "Native Hawaiian or Other Pacific Islander" ->
      utils.coding(
        code: "2076-8",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Native Hawaiian or Other Pacific Islander",
      )
    "White" ->
      utils.coding(
        code: "2106-3",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "White",
      )
    _ ->
      utils.coding(
        code: "UNK",
        system: "http://terminology.hl7.org/CodeSystem/v3-NullFlavor",
        display: "Unknown",
      )
  }
  let us_core_race = [
    r4us.UsCoreRace(text: race_display, detailed: [], omb_category: [race]),
  ]
  use address_line <- form.field(
    "address_line",
    form.parse_optional(form.parse_string),
  )
  use address_city <- form.field(
    "address_city",
    form.parse_optional(form.parse_string),
  )
  use address_state <- form.field(
    "address_state",
    form.parse_optional(form.parse_string),
  )
  use address_postal_code <- form.field(
    "address_postal_code",
    form.parse_optional(form.parse_string),
  )
  let address = case
    address_line,
    address_city,
    address_state,
    address_postal_code
  {
    None, None, None, None -> []
    _, _, _, _ -> [
      r4us.Address(
        ..r4us.address_new(),
        line: case address_line {
          Some(l) -> [l]
          None -> []
        },
        city: address_city,
        state: address_state,
        postal_code: address_postal_code,
      ),
    ]
  }
  use ethnicity_display <- form.field("ethnicity", form.parse_string)
  let ethnicity = case ethnicity_display {
    "Hispanic or Latino" ->
      utils.coding(
        code: "2135-2",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Hispanic or Latino",
      )
    "Not Hispanic or Latino" ->
      utils.coding(
        code: "2186-5",
        system: "urn:oid:2.16.840.1.113883.6.238",
        display: "Not Hispanic or Latino",
      )
    _ ->
      utils.coding(
        code: "UNK",
        system: "http://terminology.hl7.org/CodeSystem/v3-NullFlavor",
        display: "Unknown",
      )
  }
  let us_core_ethnicity = [
    r4us.UsCoreEthnicity(
      text: ethnicity_display,
      detailed: [],
      omb_category: Some(ethnicity),
    ),
  ]

  form.success(
    r4us.Patient(
      ..r4us.patient_new(),
      name: [r4us.Humanname(..r4us.humanname_new(), family:, given:)],
      birth_date: birth_date,
      telecom:,
      gender:,
      us_core_race:,
      us_core_ethnicity:,
      address:,
    ),
  )
}
