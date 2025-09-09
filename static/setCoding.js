function setCodingFromOptions(selectElement) {
  const selectedOption = selectElement.options[selectElement.selectedIndex];
  
  // Find all hidden inputs that are siblings of the select
  const siblings = selectElement.parentElement.querySelectorAll('input[type="hidden"]');
  
  // Assuming the order is always: code, system, display (based on your template)
  const codeInput = siblings[0];
  const systemInput = siblings[1]; 
  const displayInput = siblings[2];
  
  if (selectedOption.value !== "") {
    // Set values from the selected option's FHIR attributes
    codeInput.value = selectedOption.getAttribute("fhir-code") || "";
    systemInput.value = selectedOption.getAttribute("fhir-system") || "";
    displayInput.value = selectedOption.getAttribute("fhir-display") || "";
  } else {
    // Clear the hidden inputs if no option is selected
    codeInput.value = "";
    systemInput.value = "";
    displayInput.value = "";
  }
}