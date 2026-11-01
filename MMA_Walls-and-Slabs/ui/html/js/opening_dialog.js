let initialData = {
  width: 900,
  height: 2100,
  sill_height: 0,
  type: 'door'
};

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('op-width').value = initialData.width || 900;
  document.getElementById('op-height').value = initialData.height || 2100;
  document.getElementById('op-sill').value = initialData.sill_height || 0;
  document.getElementById('op-type').value = initialData.type || 'door';
});

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) window.sketchup.close_dialog();
}

function submitOpening() {
  const payload = {
    type: document.getElementById('op-type').value,
    width: parseFloat(document.getElementById('op-width').value) || 900,
    height: parseFloat(document.getElementById('op-height').value) || 2100,
    sill_height: parseFloat(document.getElementById('op-sill').value) || 0
  };
  if (window.sketchup && window.sketchup.start_placement_tool) {
    window.sketchup.start_placement_tool(JSON.stringify(payload));
  }
}
