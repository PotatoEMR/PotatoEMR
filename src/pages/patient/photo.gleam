import fhir/r4us
import fhir/r4us_rsvp
import fhir/r4us_valuesets
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import lustre
import lustre/attribute.{type Attribute} as a
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/svg
import lustre/event
import model_msgs.{type Model, Model} as mm
import utils
import utils2

pub fn update(msg, model) {
  case msg {
    mm.ServerUpdatedPatientPhoto(Error(_)) -> todo
    mm.ServerUpdatedPatientPhoto(Ok(patient)) -> server_updated(model, patient)
    mm.UserDraggingPhoto(dragging_photo) ->
      set_drag_photo(model, dragging_photo)
    mm.UserSelectedPhotoEvent(event) -> select_photo(model, event)
    mm.UserSelectedPhotoDataUrl(dataurl) -> select_daturl(model, dataurl)
    mm.UserClickedExistingPhoto(num) -> set_existing(model, num)
  }
}

pub fn select_daturl(model: Model, data_url) {
  // data_url is like "data:image/png;base64,iVBOR..."
  // split into content_type and base64 data for FHIR Attachment
  case model.route {
    mm.RoutePatient(id:, page:, patient:) ->
      case patient {
        mm.PatientLoadFound(data:) -> {
          let #(content_type, base64) = parse_data_url(data_url)
          let new_photo =
            r4us.Attachment(
              ..r4us.attachment_new(),
              content_type: Some(content_type),
              data: Some(base64),
            )
          let newpat =
            r4us.Patient(..data.patient, photo: [
              new_photo,
              ..data.patient.photo
            ])
          let effect =
            newpat
            |> r4us_rsvp.patient_update(
              model.client,
              mm.ServerUpdatedPatientPhoto,
            )
            |> result.unwrap(effect.none())
          // don't *have* to update model patient photo here
          // as the server response msg will update model
          // but if we do it here too the user gets instant feedback
          let newdata = mm.PatientData(..data, patient: newpat)
          let patient = mm.PatientLoadFound(newdata)
          let model =
            Model(..model, route: mm.RoutePatient(id:, page:, patient:))
          #(model, effect)
        }
        _ -> #(model, effect.none())
      }
    _ -> #(model, effect.none())
  }
}

pub fn select_photo(model: Model, event: dynamic.Dynamic) {
  #(
    Model(..model, dragging_photo: False),
    effect.from(fn(dispatch) {
      utils2.read_file_from_event(event, fn(data_url) {
        dispatch(mm.UserSelectedPhotoDataUrl(data_url))
      })
    }),
  )
}

fn server_updated(model: Model, patient: r4us.Patient) {
  utils2.update_patient(model, fn(pat) {
    case pat {
      mm.PatientLoadFound(data:) ->
        mm.PatientLoadFound(mm.PatientData(..data, patient:))
      _ -> pat
      // in _ case could creeate new patient data, but would be weird to be in that case
    }
  })
}

pub fn set_drag_photo(model: Model, dragging_photo: Bool) {
  case model.route {
    mm.RoutePatient(page: mm.PatientPhotos, ..) -> #(
      Model(..model, dragging_photo:),
      effect.none(),
    )
    _ -> #(model, effect.none())
  }
}

pub fn set_existing(model: Model, num: Int) {
  case model.route {
    mm.RoutePatient(id:, page:, patient:) ->
      case patient {
        mm.PatientLoadFound(data:) -> {
          case data.patient.photo {
            [] -> todo
            [first, ..] -> {
              // indicating use this picture by moving to front of list
              // is not that short but not terrible
              // but idk if json guarantueed to keep order on server
              // might be better to indicate chosen profile pic another way
              let #(move_to_front, photos) =
                list.index_fold(
                  over: data.patient.photo,
                  from: #(first, []),
                  with: fn(acc, existing_photo, idx) {
                    case idx == num {
                      True -> #(existing_photo, acc.1)
                      False -> #(acc.0, [existing_photo, ..acc.1])
                    }
                  },
                )
              let photos = list.reverse(photos)
              let photos = [move_to_front, ..photos]
              let newpat = r4us.Patient(..data.patient, photo: photos)
              let newdata = mm.PatientData(..data, patient: newpat)
              let patient = mm.PatientLoadFound(newdata)
              let effect =
                newpat
                |> r4us_rsvp.patient_update(
                  model.client,
                  mm.ServerUpdatedPatientPhoto,
                )
                |> result.unwrap(effect.none())
              let model =
                Model(..model, route: mm.RoutePatient(id:, page:, patient:))
              #(model, effect)
            }
          }
        }
        _ -> #(model, effect.none())
      }
    _ -> #(model, effect.none())
  }
}

pub fn view(model: Model, data: mm.PatientData) {
  let photos =
    list.index_map(data.patient.photo, fn(photo, num) {
      case utils.get_img_src(photo) {
        Ok(src) ->
          utils.view_patient_photo_box(
            src,
            Some(event.on_click(mm.UserClickedExistingPhoto(num))),
          )
        Error(_) -> h.div([a.class("hidden")], [])
      }
    })
  let dropzone_class = case model.dragging_photo {
    True ->
      "border-2 border-dashed border-blue-500 bg-blue-50 rounded-lg p-6 text-center transition-colors"
    False ->
      "border-2 border-dashed border-gray-300 rounded-lg p-6 text-center transition-colors"
  }
  [
    h.div([a.class("min-h-full")], [
      h.div([a.class("p-4")], [
        h.div([a.class(dropzone_class)], [
          h.h3([a.class("text-lg mb-2")], [h.text("Upload Photo")]),
          h.label(
            [
              a.class(
                "inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white font-medium rounded cursor-pointer hover:bg-blue-700 active:bg-blue-800 transition-colors",
              ),
            ],
            [
              h.text("Choose File"),
              h.input([
                a.type_("file"),
                a.attribute("accept", "image/*"),
                a.class("hidden"),
                on_file_input(mm.UserSelectedPhotoEvent),
              ]),
            ],
          ),
          h.p([a.class("mt-2 text-sm text-gray-500")], [
            h.text("or drag and drop an image anywhere on this page"),
          ]),
        ]),
      ]),
      h.div([a.class("p-4 flex flex-wrap gap-2")], photos),
    ]),
  ]
}

fn on_file_input(msg) {
  let raw_decoder = decode.new_primitive_decoder("Dynamic", fn(dyn) { Ok(dyn) })
  event.on("change", {
    use evt <- decode.then(raw_decoder)
    decode.success(msg(evt))
  })
}

fn parse_data_url(data_url: String) -> #(String, String) {
  // "data:image/png;base64,iVBOR..." -> #("image/png", "iVBOR...")
  case string.split_once(data_url, ",") {
    Ok(#(header, base64)) -> {
      let content_type =
        header
        |> string.drop_start(5)
        |> string.split_once(";")
        |> result.map(fn(pair) { pair.0 })
        |> result.unwrap("application/octet-stream")
      #(content_type, base64)
    }
    Error(_) -> #("application/octet-stream", data_url)
  }
}
