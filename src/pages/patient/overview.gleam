import gleam/option.{None, Some}
import lustre/effect
import lustre/element
import lustre/element/html as h

pub fn view(_model) {
  [h.p([], [h.text("overview")])]
}
