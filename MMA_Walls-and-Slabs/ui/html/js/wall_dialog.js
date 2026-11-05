let currentWallData = {
  height: 2800,
  justification: 'center',
  core_type: 'hollow_brick',
  end_wrap: 'none',
  core_thickness: 250,
  core_material: 'MMA_Brick',
  ext_layers: [
    { name: 'Intonaco esterno', thickness: 15, material: 'MMA_Render_Ext', enabled: true },
    { name: 'Cappotto EPS', thickness: 100, material: 'MMA_Insulation_EPS', enabled: true }
  ],
  int_layers: [
    { name: 'Intonaco interno', thickness: 15, material: 'MMA_Plaster_Int', enabled: true }
  ],
  openings: []
};
let loadedCoreType = currentWallData.core_type;
let savedWallTypes = [];
let selectedWallTypeName = '';
const layerMaterials = {
  MMA_Concrete: 'Concrete',
  MMA_Brick: 'Solid brick',
  MMA_Concrete_Block: 'Hollow concrete block',
  MMA_Metal_Stud: 'Metal studs',
  MMA_Drywall_Board: 'Drywall board',
  MMA_Insulation_EPS: 'EPS insulation',
  MMA_Render_Ext: 'Exterior render',
  MMA_Plaster_Int: 'Interior plaster',
  MMA_Screed: 'Screed',
  MMA_Wood_Flooring: 'Wood flooring',
  MMA_Ceramic_Tile: 'Ceramic tile',
  MMA_Stone_Dark: 'Stone - dark',
  MMA_Stone_Light: 'Stone - light',
  MMA_Stone_Flooring: 'Stone flooring'
};

window.addEventListener('DOMContentLoaded', () => {
  if (window.sketchup && window.sketchup.dialog_ready) window.sketchup.dialog_ready();
  renderWallData();
});

function renderWallData() {
  currentWallData.ext_layers = Array.isArray(currentWallData.ext_layers) ? currentWallData.ext_layers : [];
  currentWallData.int_layers = Array.isArray(currentWallData.int_layers) ? currentWallData.int_layers : [];
  document.getElementById('wall-height').value = currentWallData.height || 2800;
  const alignment = currentWallData.justification || 'center';
  document.getElementById('wall-justification').value =
    alignment === 'left' ? 'outer' : (alignment === 'right' ? 'inner' : alignment);
  document.getElementById('wall-end-wrap').value = currentWallData.end_wrap || 'none';
  document.getElementById('core-type').value = currentWallData.core_type || 'hollow_brick';
  document.getElementById('core-thickness').value = currentWallData.core_thickness == null ? 250 : currentWallData.core_thickness;
  renderLayerEditors();
}

function renderLayerEditors() {
  [['Exterior layers', 'ext_layers', 'exterior-layers'], ['Interior layers', 'int_layers', 'interior-layers']].forEach(([title, key, containerId]) => {
    const container = document.getElementById(containerId);
    container.replaceChildren();
    const section = document.createElement('div');
    section.className = 'layer-section';
    const heading = document.createElement('div');
    heading.className = 'layer-section-title';
    const add = document.createElement('button');
    add.type = 'button';
    add.textContent = 'Add layer';
    add.addEventListener('click', () => {
      currentWallData[key].push({ name: 'New layer', thickness: 10, material: '', enabled: true });
      renderLayerEditors();
    });
    heading.appendChild(add);
    section.appendChild(heading);
    let draggedIndex = null;
    currentWallData[key].forEach((layer, index) => {
      const row = document.createElement('div');
      row.className = 'layer-row';
      row.draggable = true;
      row.addEventListener('dragstart', event => {
        draggedIndex = index;
        event.dataTransfer.effectAllowed = 'move';
      });
      row.addEventListener('dragover', event => {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
      });
      row.addEventListener('drop', event => {
        event.preventDefault();
        if (draggedIndex === null || draggedIndex === index) return;
        const [movedLayer] = currentWallData[key].splice(draggedIndex, 1);
        currentWallData[key].splice(index, 0, movedLayer);
        renderLayerEditors();
      });
      const name = document.createElement('input');
      name.value = layer.name || '';
      name.setAttribute('aria-label', `${title} ${index + 1} name`);
      name.addEventListener('input', () => { layer.name = name.value; });
      const thickness = document.createElement('input');
      thickness.type = 'number';
      thickness.min = '0';
      thickness.step = '0.1';
      thickness.value = layer.thickness || 0;
      thickness.setAttribute('aria-label', `${title} ${index + 1} thickness in mm`);
      thickness.addEventListener('input', () => { layer.thickness = parseFloat(thickness.value) || 0; });
      const material = document.createElement('select');
      material.setAttribute('aria-label', `${title} ${index + 1} material`);
      const noMaterial = document.createElement('option');
      noMaterial.value = '';
      noMaterial.textContent = 'No material';
      material.appendChild(noMaterial);
      Object.entries(layerMaterials).forEach(([value, label]) => {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = label;
        material.appendChild(option);
      });
      if (layer.material && !Object.prototype.hasOwnProperty.call(layerMaterials, layer.material)) {
        const option = document.createElement('option');
        option.value = layer.material;
        option.textContent = layer.material;
        material.appendChild(option);
      }
      material.value = layer.material || '';
      material.addEventListener('change', () => { layer.material = material.value; });
      const enabled = document.createElement('input');
      enabled.type = 'checkbox';
      enabled.checked = layer.enabled !== false;
      enabled.setAttribute('aria-label', `Enable ${title.toLowerCase()} ${index + 1}`);
      enabled.addEventListener('change', () => { layer.enabled = enabled.checked; });
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.textContent = '×';
      remove.setAttribute('aria-label', `Remove ${title.toLowerCase()} ${index + 1}`);
      remove.addEventListener('click', () => {
        currentWallData[key].splice(index, 1);
        renderLayerEditors();
      });
      row.append(name, thickness, material, enabled, remove);
      section.appendChild(row);
    });
    container.appendChild(section);
  });
}

function loadWallData(data, createWall = false, wallTypes = []) {
  currentWallData = Object.assign({}, currentWallData, data || {});
  loadedCoreType = currentWallData.core_type;
  savedWallTypes = Array.isArray(wallTypes) ? wallTypes : [];
  selectedWallTypeName = '';
  renderWallTypeOptions();
  const badge = document.getElementById('mode-badge');
  badge.textContent = createWall
    ? 'Create Wall'
    : (currentWallData.start_point && currentWallData.end_point ? 'Edit Wall' : 'Wall Defaults');
  document.getElementById('wall-submit').textContent = createWall ? 'Okay' : 'Apply';
  renderWallData();
}

function renderWallTypeOptions() {
  const select = document.getElementById('wall-type-select');
  select.replaceChildren();
  const placeholder = document.createElement('option');
  placeholder.value = '';
  placeholder.textContent = '-- Select a saved type --';
  select.appendChild(placeholder);
  savedWallTypes.forEach(type => {
    const option = document.createElement('option');
    option.value = type.name;
    option.textContent = type.name;
    select.appendChild(option);
  });
  select.value = selectedWallTypeName;
  document.getElementById('delete-wall-type').disabled = !selectedWallTypeName;
}

document.getElementById('wall-type-select').addEventListener('change', event => {
  const wallType = savedWallTypes.find(type => type.name === event.target.value);
  if (!wallType) {
    selectedWallTypeName = '';
    document.getElementById('wall-type-name').value = '';
    renderWallTypeOptions();
    return;
  }
  selectedWallTypeName = wallType.name;
  document.getElementById('wall-type-name').value = wallType.name;
  currentWallData = Object.assign({}, wallType.parameters);
  currentWallData.wall_type = wallType.name;
  loadedCoreType = currentWallData.core_type;
  renderWallTypeOptions();
  renderWallData();
});

function newWallType() {
  selectedWallTypeName = '';
  document.getElementById('wall-type-name').value = '';
  currentWallData = {
    height: 2800,
    justification: 'center',
    core_type: 'hollow_brick',
    end_wrap: 'none',
    core_thickness: 250,
    core_material: 'MMA_Brick',
    ext_layers: [],
    int_layers: [],
    openings: [],
    wall_type: ''
  };
  loadedCoreType = currentWallData.core_type;
  renderWallTypeOptions();
  renderWallData();
}

function readWallForm() {
  currentWallData.height = parseFloat(document.getElementById('wall-height').value);
  currentWallData.justification = document.getElementById('wall-justification').value;
  currentWallData.end_wrap = document.getElementById('wall-end-wrap').value;
  currentWallData.core_type = document.getElementById('core-type').value;
  currentWallData.core_thickness = parseFloat(document.getElementById('core-thickness').value);
  const coreMaterials = {
    concrete: 'MMA_Concrete',
    hollow_brick: 'MMA_Brick',
    brick: 'MMA_Brick',
    concrete_block: 'MMA_Concrete_Block',
    drywall: 'MMA_Metal_Stud'
  };
  if (currentWallData.core_type !== loadedCoreType) {
    currentWallData.core_material = coreMaterials[currentWallData.core_type] || currentWallData.core_material;
    loadedCoreType = currentWallData.core_type;
  }
}

function saveWallType() {
  const invalid = Array.from(document.querySelectorAll('input')).find(input => !input.checkValidity());
  if (invalid) {
    invalid.reportValidity();
    return;
  }
  const name = document.getElementById('wall-type-name').value.trim();
  if (!name) {
    window.alert('Enter a wall type name before saving.');
    document.getElementById('wall-type-name').focus();
    return;
  }
  readWallForm();
  currentWallData.wall_type = name;
  if (window.sketchup && window.sketchup.save_wall_type) {
    window.sketchup.save_wall_type(JSON.stringify({ name, parameters: currentWallData }));
  } else {
    window.alert('SketchUp is not connected to the wall settings dialog.');
  }
}

function deleteWallType() {
  if (!selectedWallTypeName) return;
  if (!window.confirm(`Delete the saved wall type "${selectedWallTypeName}"?`)) return;
  if (window.sketchup && window.sketchup.delete_wall_type) {
    window.sketchup.delete_wall_type(selectedWallTypeName);
  } else {
    window.alert('SketchUp is not connected to the wall settings dialog.');
  }
}

function wallTypesUpdated(wallTypes, deletedName = '', savedName = '') {
  savedWallTypes = Array.isArray(wallTypes) ? wallTypes : [];
  if (deletedName && selectedWallTypeName === deletedName) {
    selectedWallTypeName = '';
    document.getElementById('wall-type-name').value = '';
    currentWallData.wall_type = '';
  }
  if (savedName) {
    selectedWallTypeName = savedName;
    document.getElementById('wall-type-name').value = savedName;
    currentWallData.wall_type = savedName;
  }
  renderWallTypeOptions();
}

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) window.sketchup.close_dialog();
}

function submitWall() {
  const invalid = Array.from(document.querySelectorAll('input')).find(input => !input.checkValidity());
  if (invalid) {
    invalid.reportValidity();
    return;
  }
  readWallForm();
  const typedName = document.getElementById('wall-type-name').value.trim();
  currentWallData.wall_type = selectedWallTypeName || typedName || currentWallData.wall_type || '';
  if (window.sketchup && window.sketchup.create_or_update_wall) {
    window.sketchup.create_or_update_wall(JSON.stringify(currentWallData));
  } else {
    window.alert('SketchUp is not connected to the wall settings dialog.');
  }
}
