import gleam/option.{None, Some}
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html as h

pub fn view() -> List(Element(msg)) {
  [h.p([], [h.text("index")])]
}
