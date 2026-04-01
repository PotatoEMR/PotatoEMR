import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/list
import gleam/option.{None, Some}
import gleam/uri
import lustre/attribute as a
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import modem

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

pub fn view(newpatient: Form(r4us.Patient)) {
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
