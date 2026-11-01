let initialData = {
  width: 900,
  height: 2100,
  type: 'door'
};

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('op-width').value = initialData.width || 900;
  document.getElementById('op-height').value = initialData.height || 2100;
  document.getElementById('op-type').value = initialData.type || 'door';
});

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) window.sketchup.close_dialog();
}

function submitOpening() {
  const invalid = Array.from(document.querySelectorAll('input')).find(input => !input.checkValidity());
  if (invalid) {
    invalid.reportValidity();
    return;
  }
  const payload = {
    type: document.getElementById('op-type').value,
    width: parseFloat(document.getElementById('op-width').value) || 900,
    height: parseFloat(document.getElementById('op-height').value) || 2100
  };
  if (window.sketchup && window.sketchup.start_placement_tool) {
    window.sketchup.start_placement_tool(JSON.stringify(payload));
  } else {
    window.alert('SketchUp is not connected to the opening dialog.');
  }
}
