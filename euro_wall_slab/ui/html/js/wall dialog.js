// Euro Wall Dialog Logic
let currentWallData = {
  start_point: [0, 0, 0],
  end_point: [3000, 0, 0],
  height: 2800,
  justification: 'center',
  core_type: 'poroton',
  core_thickness: 250,
  core_material: 'EWS_Laterizio',
  drywall_stud_spacing: 600,
  drywall_boards_ext: 2,
  drywall_boards_int: 2,
  drywall_board_thick: 12.5,
  start_edge: 'open',
  end_edge: 'open',
  ext_layers: [
    { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true },
    { name: 'Cappotto EPS', thickness: 100, material: 'EWS_Insulation_EPS', enabled: true }
  ],
  int_layers: [
    { name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
  ],
  openings: []
};

let isEditing = false;

// Standard materials list
const AVAILABLE_MATERIALS = [
  'EWS_Laterizio',
  'EWS_Concrete',
  'EWS_Brick',
  'EWS_Ytong',
  'EWS_Render_Ext',
  'EWS_Plaster_Int',
  'EWS_Insulation_EPS',
  'EWS_Drywall_Board',
  'EWS_Metal_Stud'
];

window.addEventListener('DOMContentLoaded', () => {
  // Request data from SketchUp Ruby
  if (window.sketchup && window.sketchup.get_initial_data) {
    window.sketchup.get_initial_data();
  } else {
    // Standalone / preview mode
    renderUI();
  }
});

function initData(data) {
  if (data) {
    currentWallData = Object.assign({}, currentWallData, data);
    isEditing = !!data.is_editing;
  }
  document.getElementById('mode-badge').textContent = isEditing ? 'Edit Wall' : 'New Wall';
  renderUI();
}

function renderUI() {
  document.getElementById('wall-height').value = currentWallData.height || 2800;
  document.getElementById('wall-justification').value = currentWallData.justification || 'center';
  document.getElementById('wall-start-edge').value = currentWallData.start_edge || 'open';
  document.getElementById('wall-end-edge').value = currentWallData.end_edge || 'open';
  document.getElementById('core-type').value = currentWallData.core_type || 'poroton';
  document.getElementById('core-thickness').value = currentWallData.core_thickness || 250;
  document.getElementById('core-material').value = currentWallData.core_material || 'EWS_Laterizio';

  document.getElementById('drywall-spacing').value = currentWallData.drywall_stud_spacing || 600;
  document.getElementById('drywall-board-thick').value = currentWallData.drywall_board_thick || 12.5;
  document.getElementById('drywall-boards-ext').value = currentWallData.drywall_boards_ext || 2;
  document.getElementById('drywall-boards-int').value = currentWallData.drywall_boards_int || 2;

  onCoreTypeChange();
  renderLayersTable('ext');
  renderLayersTable('int');
  renderOpenings();
}

function onCoreTypeChange() {
  const coreType = document.getElementById('core-type').value;
  const isDrywall = coreType === 'drywall';

  document.getElementById('drywall-options').style.display = isDrywall ? 'block' : 'none';
  document.getElementById('core-mat-group').style.display = isDrywall ? 'none' : 'flex';

  // Set default thickness per core if unchanged
  const thkInput = document.getElementById('core-thickness');
  if (isDrywall) {
    thkInput.value = 75; // Stud width
  } else if (coreType === 'poroton') {
    thkInput.value = 250;
    document.getElementById('core-material').value = 'EWS_Laterizio';
  } else if (coreType === 'concrete') {
    thkInput.value = 200;
    document.getElementById('core-material').value = 'EWS_Concrete';
  } else if (coreType === 'brick') {
    thkInput.value = 120;
    document.getElementById('core-material').value = 'EWS_Brick';
  } else if (coreType === 'aac_block') {
    thkInput.value = 200;
    document.getElementById('core-material').value = 'EWS_Ytong';
  }
}

function renderLayersTable(type) {
  const tbody = document.getElementById(`${type}-layers-body`);
  tbody.innerHTML = '';
  const layers = type === 'ext' ? currentWallData.ext_layers : currentWallData.int_layers;

  layers.forEach((layer, idx) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><input type="text" value="${escapeHtml(layer.name)}" onchange="updateLayer('${type}', ${idx}, 'name', this.value)" style="width: 100%;"></td>
      <td><input type="number" value="${layer.thickness}" min="1" step="1" onchange="updateLayer('${type}', ${idx}, 'thickness', parseFloat(this.value))" style="width: 75px;"></td>
      <td>
        <select onchange="updateLayer('${type}', ${idx}, 'material', this.value)" style="width: 130px;">
          ${AVAILABLE_MATERIALS.map(m => `<option value="${m}" ${m === layer.material ? 'selected' : ''}>${m.replace('EWS_', '')}</option>`).join('')}
        </select>
      </td>
      <td><button class="btn-icon" onclick="removeLayer('${type}', ${idx})" title="Remove layer">✕</button></td>
    `;
    tbody.appendChild(tr);
  });
}

function addLayer(type) {
  const defaultName = type === 'ext' ? 'New Ext Layer' : 'New Int Layer';
  const defaultMat = type === 'ext' ? 'EWS_Insulation_EPS' : 'EWS_Plaster_Int';
  const newLayer = { name: defaultName, thickness: 20, material: defaultMat, enabled: true };

  if (type === 'ext') {
    currentWallData.ext_layers.push(newLayer);
  } else {
    currentWallData.int_layers.push(newLayer);
  }
  renderLayersTable(type);
}

function updateLayer(type, idx, field, value) {
  const layers = type === 'ext' ? currentWallData.ext_layers : currentWallData.int_layers;
  if (layers[idx]) {
    layers[idx][field] = value;
  }
}

function removeLayer(type, idx) {
  const layers = type === 'ext' ? currentWallData.ext_layers : currentWallData.int_layers;
  layers.splice(idx, 1);
  renderLayersTable(type);
}

function renderOpenings() {
  const card = document.getElementById('openings-card');
  const container = document.getElementById('openings-container');
  const ops = currentWallData.openings || [];

  if (!isEditing || ops.length === 0) {
    card.style.display = 'none';
    return;
  }

  card.style.display = 'block';
  container.innerHTML = '';

  ops.forEach(op => {
    const item = document.createElement('div');
    item.className = 'opening-item';
    item.innerHTML = `
      <span><strong>${op.type.toUpperCase()}:</strong> ${op.width}x${op.height} mm (Sill: ${op.sill_height}mm) @ offset ${op.offset_x}mm</span>
      <button class="btn-icon" onclick="deleteOpening('${op.id}')" title="Delete Opening">✕</button>
    `;
    container.appendChild(item);
  });
}

function deleteOpening(opId) {
  currentWallData.openings = currentWallData.openings.filter(o => o.id !== opId);
  renderOpenings();
}

function applyPreset(presetKey) {
  switch (presetKey) {
    case 'ext_laterizio_cappotto':
      currentWallData.core_type = 'poroton';
      currentWallData.core_thickness = 250;
      currentWallData.core_material = 'EWS_Laterizio';
      currentWallData.ext_layers = [
        { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true },
        { name: 'Cappotto EPS', thickness: 100, material: 'EWS_Insulation_EPS', enabled: true }
      ];
      currentWallData.int_layers = [
        { name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
      ];
      break;

    case 'ext_concrete_cappotto':
      currentWallData.core_type = 'concrete';
      currentWallData.core_thickness = 250;
      currentWallData.core_material = 'EWS_Concrete';
      currentWallData.ext_layers = [
        { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true },
        { name: 'Cappotto EPS', thickness: 140, material: 'EWS_Insulation_EPS', enabled: true }
      ];
      currentWallData.int_layers = [
        { name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
      ];
      break;

    case 'int_laterizio':
      currentWallData.core_type = 'poroton';
      currentWallData.core_thickness = 80;
      currentWallData.core_material = 'EWS_Laterizio';
      currentWallData.ext_layers = [
        { name: 'Intonaco', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
      ];
      currentWallData.int_layers = [
        { name: 'Intonaco', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
      ];
      break;

    case 'drywall_double':
      currentWallData.core_type = 'drywall';
      currentWallData.core_thickness = 75;
      currentWallData.drywall_stud_spacing = 600;
      currentWallData.drywall_boards_ext = 2;
      currentWallData.drywall_boards_int = 2;
      currentWallData.drywall_board_thick = 12.5;
      currentWallData.ext_layers = [];
      currentWallData.int_layers = [];
      break;

    case 'solid_brick':
      currentWallData.core_type = 'brick';
      currentWallData.core_thickness = 250;
      currentWallData.core_material = 'EWS_Brick';
      currentWallData.ext_layers = [
        { name: 'Intonaco esterno', thickness: 15, material: 'EWS_Render_Ext', enabled: true }
      ];
      currentWallData.int_layers = [
        { name: 'Intonaco interno', thickness: 15, material: 'EWS_Plaster_Int', enabled: true }
      ];
      break;
  }
  renderUI();
}

function submitWall() {
  currentWallData.height = parseFloat(document.getElementById('wall-height').value) || 2800;
  currentWallData.justification = document.getElementById('wall-justification').value;
  currentWallData.start_edge = document.getElementById('wall-start-edge').value;
  currentWallData.end_edge = document.getElementById('wall-end-edge').value;
  currentWallData.core_type = document.getElementById('core-type').value;
  currentWallData.core_thickness = parseFloat(document.getElementById('core-thickness').value) || 200;
  currentWallData.core_material = document.getElementById('core-material').value;

  if (currentWallData.core_type === 'drywall') {
    currentWallData.drywall_stud_spacing = parseFloat(document.getElementById('drywall-spacing').value) || 600;
    currentWallData.drywall_board_thick = parseFloat(document.getElementById('drywall-board-thick').value) || 12.5;
    currentWallData.drywall_boards_ext = parseInt(document.getElementById('drywall-boards-ext').value, 10) || 1;
    currentWallData.drywall_boards_int = parseInt(document.getElementById('drywall-boards-int').value, 10) || 1;
  }

  if (window.sketchup && window.sketchup.create_or_update_wall) {
    window.sketchup.create_or_update_wall(JSON.stringify(currentWallData));
  }
}

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) {
    window.sketchup.close_dialog();
  }
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.innerText = text;
  return div.innerHTML;
}
