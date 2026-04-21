import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import formal/form.{type Form}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import terminology/substancecodes
import utils
import utils2

pub type CodingOption {
  CodingOption(code: String, display: String, system: String)
}

pub fn btn_attrs() {
  [
    a.class("text-sm font-bold px-4 py-2 rounded-lg cursor-pointer"),
    a.class("border border-slate-700 text-slate-200 bg-slate-800"),
    a.class("hover:bg-slate-700"),
  ]
}

pub fn btn(label: String, on_click msg: msg) -> Element(msg) {
  h.button([event.on_click(msg), ..btn_attrs()], [h.text(label)])
}

pub fn btn_cancel(label: String, on_click msg: msg) -> Element(msg) {
  h.button([a.type_("button"), event.on_click(msg), ..btn_attrs()], [
    h.text(label),
  ])
}

pub fn btn_nomsg(label: String) -> Element(msg) {
  h.button(btn_attrs(), [h.text(label)])
}

pub fn view_form_select(
  form: Form(a),
  name name: String,
  options options: List(String),
  label label: String,
) {
  let errors = form.field_error_messages(form, name)
  let current_value = form.field_value(form, name)

  h.div([], [
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
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
        a.id(name),
        a.name(name),
      ],
      [
        h.option([a.value(""), a.selected(current_value == "")], "----"),
        ..list.map(options, fn(option) {
          h.option(
            [a.value(option), a.selected(current_value == option)],
            option,
          )
        })
      ],
    ),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

pub fn view_form_coding_select(
  form: Form(a),
  name name: String,
  options options: List(CodingOption),
  label label: String,
) {
  let errors = form.field_error_messages(form, name)
  let current_value = form.field_value(form, name)

  h.div([], [
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
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
        a.id(name),
        a.name(name),
      ],
      [
        h.option([a.value(""), a.selected(current_value == "")], "----"),
        ..list.map(options, fn(option) {
          h.option(
            [a.value(option.code), a.selected(current_value == option.code)],
            option.display,
          )
        })
      ],
    ),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

pub fn view_form_textarea(
  form: Form(a),
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  h.div([a.class("w-full")], [
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.textarea(
      [
        a.class("border border-slate-700 bg-slate-950 w-full resize"),
        case errors {
          [] -> a.class("focus:outline focus:outline-purple-600")
          _ -> a.class("outline outline-red-500")
        },
        a.id(name),
        a.name(name),
        a.attribute("rows", "3"),
      ],
      form.field_value(form, name),
    ),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

pub fn view_form_input(
  form: Form(a),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  h.div([], [
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
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
      a.id(name),
      a.name(name),
      a.value(form.field_value(form, name)),
    ]),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}

pub fn view_form_input_wide(
  form: Form(a),
  is type_: String,
  name name: String,
  label label: String,
) -> Element(msg) {
  let errors = form.field_error_messages(form, name)

  h.div([a.class("w-96 max-w-full")], [
    h.label([a.for(name), a.class("block text-xs font-bold text-slate-600")], [
      h.text(label),
      h.text(": "),
    ]),
    h.input([
      a.type_(type_),
      a.class("border border-slate-700 bg-slate-950 w-full"),
      case errors {
        [] -> a.class("focus:outline focus:outline-purple-600")
        _ -> a.class("outline outline-red-500")
      },
      a.id(name),
      a.name(name),
      a.value(form.field_value(form, name)),
    ]),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs text-red-500")], [
        h.text(error_message),
      ])
    })
  ])
}
