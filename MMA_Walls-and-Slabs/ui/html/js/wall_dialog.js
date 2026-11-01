let currentWallData = {
  height: 2800,
  justification: 'center',
  core_type: 'poroton',
  core_thickness: 250,
  core_material: 'EWS_Laterizio',
  ext_layers: [
    { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true },
    { name: 'Cappotto EPS', thickness: 100, material: 'EWS_Insulation_EPS', enabled: true }
  ],
  int_layers: [
    { name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
  ],
  openings: []
};

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('wall-height').value = currentWallData.height || 2800;
  document.getElementById('wall-justification').value = currentWallData.justification || 'center';
  document.getElementById('core-type').value = currentWallData.core_type || 'poroton';
});

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) window.sketchup.close_dialog();
}

function submitWall() {
  currentWallData.height = parseFloat(document.getElementById('wall-height').value) || 2800;
  currentWallData.justification = document.getElementById('wall-justification').value;
  currentWallData.core_type = document.getElementById('core-type').value;
  if (window.sketchup && window.sketchup.create_or_update_wall) {
    window.sketchup.create_or_update_wall(JSON.stringify(currentWallData));
  }
}

function applyPreset(key) {
  switch (key) {
    case 'ext_laterizio_cappotto':
      currentWallData.core_type = 'poroton';
      currentWallData.core_thickness = 250;
      currentWallData.core_material = 'EWS_Laterizio';
      currentWallData.ext_layers = [
        { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true },
        { name: 'Cappotto EPS', thickness: 100, material: 'EWS_Insulation_EPS', enabled: true }
      ];
      currentWallData.int_layers = [{ name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }];
      break;
    case 'ext_concrete_cappotto':
      currentWallData.core_type = 'concrete';
      currentWallData.core_thickness = 250;
      currentWallData.core_material = 'EWS_Concrete';
      currentWallData.ext_layers = [
        { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true },
        { name: 'Cappotto EPS', thickness: 140, material: 'EWS_Insulation_EPS', enabled: true }
      ];
      currentWallData.int_layers = [{ name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }];
      break;
    case 'int_laterizio':
      currentWallData.core_type = 'poroton';
      currentWallData.core_thickness = 80;
      currentWallData.core_material = 'EWS_Laterizio';
      currentWallData.ext_layers = [{ name: 'Intonaco', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }];
      currentWallData.int_layers = [{ name: 'Intonaco', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }];
      break;
    case 'drywall_double':
      currentWallData.core_type = 'drywall';
      currentWallData.core_thickness = 75;
      currentWallData.ext_layers = [];
      currentWallData.int_layers = [];
      break;
  }
}
