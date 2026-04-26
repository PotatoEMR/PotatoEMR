import formal/form.{type Form}
import gleam/list
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import colors

pub type CodingOption {
  CodingOption(code: String, display: String, system: String)
}

pub fn btn_attrs() {
  [
    a.class("text-sm font-bold px-4 py-2 rounded-lg cursor-pointer"),
    a.class("border " <> colors.border_surface_0 <> " " <> colors.text <> " " <> colors.bg_base),
    a.class(colors.hover_bg_surface_0),
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
    h.label([a.for(name), a.class("block text-xs font-bold " <> colors.subtext_0)], [
      h.text(label),
      h.text(": "),
    ]),
    h.select(
      [
        a.class("border " <> colors.border_surface_0 <> " " <> colors.bg_crust),
        case errors {
          [] -> a.class("focus:outline " <> colors.focus_outline_mauve)
          _ -> a.class("outline " <> colors.outline_red)
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
      h.p([a.class("mt-0.5 text-xs " <> colors.text_red_500_error)], [
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
    h.label([a.for(name), a.class("block text-xs font-bold " <> colors.subtext_0)], [
      h.text(label),
      h.text(": "),
    ]),
    h.select(
      [
        a.class("border " <> colors.border_surface_0 <> " " <> colors.bg_crust),
        case errors {
          [] -> a.class("focus:outline " <> colors.focus_outline_mauve)
          _ -> a.class("outline " <> colors.outline_red)
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
      h.p([a.class("mt-0.5 text-xs " <> colors.text_red_500_error)], [
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
    h.label([a.for(name), a.class("block text-xs font-bold " <> colors.subtext_0)], [
      h.text(label),
      h.text(": "),
    ]),
    h.textarea(
      [
        a.class("border " <> colors.border_surface_0 <> " " <> colors.bg_crust <> " w-full resize"),
        case errors {
          [] -> a.class("focus:outline " <> colors.focus_outline_mauve)
          _ -> a.class("outline " <> colors.outline_red)
        },
        a.id(name),
        a.name(name),
        a.attribute("rows", "3"),
      ],
      form.field_value(form, name),
    ),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs " <> colors.text_red_500_error)], [
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
    h.label([a.for(name), a.class("block text-xs font-bold " <> colors.subtext_0)], [
      h.text(label),
      h.text(": "),
    ]),
    h.input([
      a.type_(type_),
      a.class("border " <> colors.border_surface_0 <> " " <> colors.bg_crust),
      case errors {
        [] -> a.class("focus:outline " <> colors.focus_outline_mauve)
        _ -> a.class("outline " <> colors.outline_red)
      },
      a.id(name),
      a.name(name),
      a.value(form.field_value(form, name)),
    ]),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs " <> colors.text_red_500_error)], [
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
    h.label([a.for(name), a.class("block text-xs font-bold " <> colors.subtext_0)], [
      h.text(label),
      h.text(": "),
    ]),
    h.input([
      a.type_(type_),
      a.class("border " <> colors.border_surface_0 <> " " <> colors.bg_crust <> " w-full"),
      case errors {
        [] -> a.class("focus:outline " <> colors.focus_outline_mauve)
        _ -> a.class("outline " <> colors.outline_red)
      },
      a.id(name),
      a.name(name),
      a.value(form.field_value(form, name)),
    ]),
    ..list.map(errors, fn(error_message) {
      h.p([a.class("mt-0.5 text-xs " <> colors.text_red_500_error)], [
        h.text(error_message),
      ])
    })
  ])
}

pub fn data_table(
  head head: Element(msg),
  rows rows: List(Element(msg)),
) -> Element(msg) {
  h.table(
    [a.class("border-collapse border " <> colors.border_surface_0 <> " w-full")],
    [h.thead([], [head]), h.tbody([], rows)],
  )
}

pub fn data_table_row(cells: List(Element(msg))) -> Element(msg) {
  h.tr([a.class("border-b " <> colors.border_surface_0)], cells)
}

pub fn form_fieldset_class() -> String {
  "border "
  <> colors.border_surface_0
  <> " rounded-lg p-4 flex flex-row flex-wrap gap-4"
}
