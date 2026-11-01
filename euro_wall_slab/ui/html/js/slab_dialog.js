// Euro Slab Dialog Logic
let currentSlabData = {
  points: [],
  elevation: 0,
  reference: 'top',
  layers: [
    { name: 'Wood Parquet', thickness: 15, material: 'EWS_Wood_Flooring', enabled: true },
    { name: 'Screed (Massetto)', thickness: 60, material: 'EWS_Screed', enabled: true },
    { name: 'Acoustic/EPS Foam', thickness: 40, material: 'EWS_Insulation_EPS', enabled: true },
    { name: 'Structural Concrete', thickness: 200, material: 'EWS_Concrete', enabled: true }
  ],
  openings: []
};

let isEditing = false;

const AVAILABLE_MATERIALS = [
  'EWS_Concrete',
  'EWS_Screed',
  'EWS_Wood_Flooring',
  'EWS_Ceramic_Tile',
  'EWS_Insulation_EPS',
  'EWS_Laterizio',
  'EWS_Ytong'
];

window.addEventListener('DOMContentLoaded', () => {
  if (window.sketchup && window.sketchup.get_initial_data) {
    window.sketchup.get_initial_data();
  } else {
    renderUI();
  }
});

function initData(data) {
  if (data) {
    currentSlabData = Object.assign({}, currentSlabData, data);
    isEditing = !!data.is_editing;
  }
  document.getElementById('mode-badge').textContent = isEditing ? 'Edit Slab' : 'New Slab';
  renderUI();
}

function renderUI() {
  document.getElementById('slab-elevation').value = currentSlabData.elevation || 0;
  document.getElementById('slab-reference').value = currentSlabData.reference || 'top';
  renderLayersTable();
}

function renderLayersTable() {
  const tbody = document.getElementById('slab-layers-body');
  tbody.innerHTML = '';

  (currentSlabData.layers || []).forEach((layer, idx) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><input type="text" value="${escapeHtml(layer.name)}" onchange="updateLayer(${idx}, 'name', this.value)" style="width: 100%;"></td>
      <td><input type="number" value="${layer.thickness}" min="1" step="5" onchange="updateLayer(${idx}, 'thickness', parseFloat(this.value))" style="width: 75px;"></td>
      <td>
        <select onchange="updateLayer(${idx}, 'material', this.value)" style="width: 130px;">
          ${AVAILABLE_MATERIALS.map(m => `<option value="${m}" ${m === layer.material ? 'selected' : ''}>${m.replace('EWS_', '')}</option>`).join('')}
        </select>
      </td>
      <td><button class="btn-icon" onclick="removeLayer(${idx})" title="Remove layer">✕</button></td>
    `;
    tbody.appendChild(tr);
  });
}

function addLayer() {
  currentSlabData.layers.push({
    name: 'New Layer',
    thickness: 50,
    material: 'EWS_Concrete',
    enabled: true
  });
  renderLayersTable();
}

function updateLayer(idx, field, value) {
  if (currentSlabData.layers[idx]) {
    currentSlabData.layers[idx][field] = value;
  }
}

function removeLayer(idx) {
  currentSlabData.layers.splice(idx, 1);
  renderLayersTable();
}

function applyPreset(presetKey) {
  switch (presetKey) {
    case 'standard_wood':
      currentSlabData.layers = [
        { name: 'Wood Parquet', thickness: 15, material: 'EWS_Wood_Flooring', enabled: true },
        { name: 'Screed (Massetto)', thickness: 60, material: 'EWS_Screed', enabled: true },
        { name: 'Acoustic/EPS Foam', thickness: 40, material: 'EWS_Insulation_EPS', enabled: true },
        { name: 'Structural Concrete', thickness: 200, material: 'EWS_Concrete', enabled: true }
      ];
      break;

    case 'standard_tile':
      currentSlabData.layers = [
        { name: 'Ceramic Tile', thickness: 12, material: 'EWS_Ceramic_Tile', enabled: true },
        { name: 'Screed (Massetto)', thickness: 60, material: 'EWS_Screed', enabled: true },
        { name: 'Acoustic/EPS Foam', thickness: 40, material: 'EWS_Insulation_EPS', enabled: true },
        { name: 'Structural Concrete', thickness: 200, material: 'EWS_Concrete', enabled: true }
      ];
      break;

    case 'concrete_mono':
      currentSlabData.layers = [
        { name: 'Structural Concrete', thickness: 200, material: 'EWS_Concrete', enabled: true }
      ];
      break;

    case 'roof_insulated':
      currentSlabData.layers = [
        { name: 'Protective Screed', thickness: 50, material: 'EWS_Screed', enabled: true },
        { name: 'Thermal EPS Insulation', thickness: 120, material: 'EWS_Insulation_EPS', enabled: true },
        { name: 'Structural Concrete', thickness: 250, material: 'EWS_Concrete', enabled: true }
      ];
      break;
  }
  renderUI();
}

function submitSlab() {
  currentSlabData.elevation = parseFloat(document.getElementById('slab-elevation').value) || 0;
  currentSlabData.reference = document.getElementById('slab-reference').value;

  if (window.sketchup && window.sketchup.create_or_update_slab) {
    window.sketchup.create_or_update_slab(JSON.stringify(currentSlabData));
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
