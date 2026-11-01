// Euro Opening Dialog Logic
let initialData = {
  width: 900,
  height: 2100,
  sill_height: 0,
  type: 'door'
};

window.addEventListener('DOMContentLoaded', () => {
  if (window.sketchup && window.sketchup.get_initial_data) {
    window.sketchup.get_initial_data();
  } else {
    renderUI();
  }
});

function initData(data) {
  if (data) {
    initialData = Object.assign({}, initialData, data);
  }
  renderUI();
}

function renderUI() {
  document.getElementById('op-width').value = initialData.width || 900;
  document.getElementById('op-height').value = initialData.height || 2100;
  document.getElementById('op-sill').value = initialData.sill_height || 0;
  document.getElementById('op-type').value = initialData.type || 'door';
}

function onTypeChange() {
  const type = document.getElementById('op-type').value;
  if (type === 'door') {
    document.getElementById('op-width').value = 900;
    document.getElementById('op-height').value = 2100;
    document.getElementById('op-sill').value = 0;
  } else if (type === 'window') {
    document.getElementById('op-width').value = 1200;
    document.getElementById('op-height').value = 1400;
    document.getElementById('op-sill').value = 900;
  }
}

function applyPreset(presetKey) {
  switch (presetKey) {
    case 'std_door':
      document.getElementById('op-type').value = 'door';
      document.getElementById('op-width').value = 900;
      document.getElementById('op-height').value = 2100;
      document.getElementById('op-sill').value = 0;
      break;
    case 'double_door':
      document.getElementById('op-type').value = 'door';
      document.getElementById('op-width').value = 1600;
      document.getElementById('op-height').value = 2100;
      document.getElementById('op-sill').value = 0;
      break;
    case 'std_window':
      document.getElementById('op-type').value = 'window';
      document.getElementById('op-width').value = 1200;
      document.getElementById('op-height').value = 1400;
      document.getElementById('op-sill').value = 900;
      break;
    case 'french_window':
      document.getElementById('op-type').value = 'window';
      document.getElementById('op-width').value = 1400;
      document.getElementById('op-height').value = 2200;
      document.getElementById('op-sill').value = 0;
      break;
    case 'small_window':
      document.getElementById('op-type').value = 'window';
      document.getElementById('op-width').value = 800;
      document.getElementById('op-height').value = 600;
      document.getElementById('op-sill').value = 1500;
      break;
  }
}

function submitAndPlace() {
  const payload = {
    type: document.getElementById('op-type').value,
    width: parseFloat(document.getElementById('op-width').value) || 900,
    height: parseFloat(document.getElementById('op-height').value) || 2100,
    sill_height: parseFloat(document.getElementById('op-sill').value) || 0
  };

  if (window.sketchup && window.sketchup.start_placement_tool) {
    window.sketchup.start_placement_tool(JSON.stringify(payload));
  } else if (window.sketchup && window.sketchup.add_opening) {
    window.sketchup.add_opening(JSON.stringify(payload));
  }
}

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) {
    window.sketchup.close_dialog();
  }
}
