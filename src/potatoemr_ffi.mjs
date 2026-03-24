export function read_file_from_event(event, callback) {
  const file = event.target?.files?.[0] || event.dataTransfer?.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => callback(reader.result);
  reader.readAsDataURL(file);
}

export function setup_body_dropzone(on_drag, on_drop_file) {
  let counter = 0;
  document.body.addEventListener("dragover", (e) => e.preventDefault());
  document.body.addEventListener("dragenter", (e) => {
    e.preventDefault();
    counter++;
    if (counter === 1) on_drag(true);
  });
  document.body.addEventListener("dragleave", (e) => {
    counter--;
    if (counter === 0) on_drag(false);
  });
  document.body.addEventListener("drop", (e) => {
    e.preventDefault();
    counter = 0;
    on_drag(false);
    const file = e.dataTransfer?.files?.[0];
    if (!file || !file.type.startsWith("image/")) return;
    const reader = new FileReader();
    reader.onload = () => on_drop_file(reader.result);
    reader.readAsDataURL(file);
  });
}
