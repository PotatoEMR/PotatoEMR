import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre
import lustre/attribute.{type Attribute} as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/svg
import lustre/event
import model_msgs.{type Model, type Msg, Model} as mm
import pages/general/registerpatient
import utils

pub fn view(_model) {
  [h.p([], [h.text("overview")])]
}
