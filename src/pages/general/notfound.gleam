import gleam/option.{None, Some}
import lustre/effect
import lustre/element
import lustre/element/html as h

pub fn view(not_found: String) {
  [h.p([], [h.text(not_found)])]
}
