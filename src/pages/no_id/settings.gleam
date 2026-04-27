import fhir/r4us_rsvp
import gleam/list
import gleam/uri
import lustre/attribute as a
import lustre/effect
import lustre/element/html as h
import lustre/event
import model_msgs.{type Model, Model} as mm
import utils2

pub fn update(msg, model) {
  case msg {
    mm.UserClickedChangeClient(baseurl) -> switch_client(model, baseurl)
  }
}

pub fn switch_client(model: Model, baseurl: String) {
  let client = r4us_rsvp.fhirclient_new(baseurl)
  case client {
    Ok(client) -> #(
      Model(..model, client:),
      effect.from(fn(_dispatch) { utils2.set_item("fhir_server", baseurl) }),
    )
    Error(_) -> #(model, effect.none())
  }
}

pub fn view(model: Model) {
  let servers = [
    "https://r4.smarthealthit.org/",
    "https://hapi.fhir.org/baseR4",
    "https://server.fire.ly",
    "http://localhost:8080/fhir/",
  ]
  [
    h.p([], [h.text("Settings")]),
    h.div([a.class("mt-8")], [
      h.p([a.class("mb-4 text-lg")], [h.text("FHIR Server Base URL")]),
      h.div(
        [],
        list.map(servers, fn(url) {
          h.label(
            [
              a.class("my-2 block"),
              event.on_click(mm.UserClickedChangeClient(url)),
            ],
            [
              h.input([
                a.type_("radio"),
                a.name("fhir-server"),
                a.checked(uri.parse(url) == Ok(model.client.baseurl)),
              ]),
              h.span([a.class("ml-2")], [h.text(url)]),
            ],
          )
        }),
      ),
    ]),
  ]
}
