import lustre/element.{type Element}
import lustre/element/html as h

pub fn view() -> List(Element(msg)) {
  [h.p([], [h.text("try searching a patient name, or registering a new patient")])]
}
