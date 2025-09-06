function setCodingFromOptions(selectElement) {
  const selectedOption = selectElement.options[selectElement.selectedIndex];

  // Get the field name prefix by removing ".display" from the select name
  const fieldPrefix = selectElement.name.replace(".display", "");

  // Find the hidden inputs that are siblings of this select element
  const container = selectElement.parentElement;
  const codeInput = container.querySelector(
    `input[name="${fieldPrefix}.code"]`,
  );
  const systemInput = container.querySelector(
    `input[name="${fieldPrefix}.system"]`,
  );
  const displayInput = container.querySelector(
    `input[name="${fieldPrefix}.display"]`,
  );

  if (selectedOption && selectedOption.value !== "") {
    // Set values from the selected option's FHIR attributes
    if (codeInput)
      codeInput.value = selectedOption.getAttribute("fhir-code") || "";
    if (systemInput)
      systemInput.value = selectedOption.getAttribute("fhir-system") || "";
    if (displayInput)
      displayInput.value = selectedOption.getAttribute("fhir-display") || "";
  } else {
    // Clear the hidden inputs if no option is selected
    if (codeInput) codeInput.value = "";
    if (systemInput) systemInput.value = "";
    if (displayInput) displayInput.value = "";
  }
}
