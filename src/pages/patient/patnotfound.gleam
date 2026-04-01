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

pub fn view() {
  svg.svg(
    [
      a.attribute("width", "150px"),
      a.attribute("height", "150px"),
      a.attribute("viewBox", "0 0 150 150"),
      a.attribute("alt", "Patient Photo"),
      a.class("mx-auto block rounded"),
    ],
    [
      svg.path([
        a.attribute("fill", "#ccc"),
        a.attribute(
          "d",
          "M 104.68731,56.689353 C 102.19435,80.640493 93.104981,97.26875 74.372196,97.26875 55.639402,97.26875 46.988823,82.308034 44.057005,57.289941 41.623314,34.938838 55.639402,15.800152 74.372196,15.800152 c 18.732785,0 32.451944,18.493971 30.315114,40.889201 z",
        ),
      ]),
      svg.path([
        a.attribute("fill", "#ccc"),
        a.attribute(
          "d",
          "M 92.5675 89.6048 C 90.79484 93.47893 89.39893 102.4504 94.86478 106.9039 C 103.9375 114.2963 106.7064 116.4723 118.3117 118.9462 C 144.0432 124.4314 141.6492 138.1543 146.5244 149.2206 L 4.268444 149.1023 C 8.472223 138.6518 6.505799 124.7812 32.40051 118.387 C 41.80992 116.0635 45.66513 113.8823 53.58659 107.0158 C 58.52744 102.7329 57.52583 93.99267 56.43084 89.26926 C 52.49275 88.83011 94.1739 88.14054 92.5675 89.6048 z",
        ),
      ]),
    ],
  )
}
