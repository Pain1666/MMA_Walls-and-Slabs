let currentSlabData = {
  points: [],
  elevation: 0,
  reference: 'top',
  layers: [
    { name: 'Wood Parquet', thickness: 15, material: 'MMA_Wood_Flooring', enabled: true },
    { name: 'Screed (Massetto)', thickness: 60, material: 'MMA_Screed', enabled: true },
    { name: 'Acoustic/EPS Foam', thickness: 40, material: 'MMA_Insulation_EPS', enabled: true },
    { name: 'Structural Concrete', thickness: 200, material: 'MMA_Concrete', enabled: true }
  ],
  openings: []
};

window.addEventListener('DOMContentLoaded', () => {
  if (window.sketchup && window.sketchup.dialog_ready) window.sketchup.dialog_ready();
  renderSlabData();
});

function renderSlabData() {
  currentSlabData.layers = Array.isArray(currentSlabData.layers) ? currentSlabData.layers : [];
  document.getElementById('slab-elevation').value = currentSlabData.elevation || 0;
  document.getElementById('slab-reference').value = currentSlabData.reference || 'top';
  renderLayerEditors();
}

function loadSlabData(data) {
  currentSlabData = Object.assign({}, currentSlabData, data || {});
  document.getElementById('mode-badge').textContent =
    Array.isArray(currentSlabData.points) && currentSlabData.points.length >= 3 ? 'Edit Slab' : 'Slab Defaults';
  renderSlabData();
}

function renderLayerEditors() {
  const container = document.getElementById('slab-layers');
  container.replaceChildren();
  const heading = document.createElement('div');
  heading.className = 'layer-section-title';
  const add = document.createElement('button');
  add.type = 'button';
  add.textContent = 'Add layer';
  add.addEventListener('click', () => {
    currentSlabData.layers.push({ name: 'New layer', thickness: 10, material: '', enabled: true });
    renderLayerEditors();
  });
  heading.append(document.createTextNode('Layers'), add);
  container.appendChild(heading);
  currentSlabData.layers.forEach((layer, index) => {
    const row = document.createElement('div');
    row.className = 'layer-row';
    const name = document.createElement('input');
    name.value = layer.name || '';
    name.setAttribute('aria-label', `Slab layer ${index + 1} name`);
    name.addEventListener('input', () => { layer.name = name.value; });
    const thickness = document.createElement('input');
    thickness.type = 'number';
    thickness.min = '0';
    thickness.step = '0.1';
    thickness.value = layer.thickness || 0;
    thickness.setAttribute('aria-label', `Slab layer ${index + 1} thickness in mm`);
    thickness.addEventListener('input', () => { layer.thickness = parseFloat(thickness.value) || 0; });
    const material = document.createElement('input');
    material.value = layer.material || '';
    material.setAttribute('aria-label', `Slab layer ${index + 1} material`);
    material.addEventListener('input', () => { layer.material = material.value; });
    const enabled = document.createElement('input');
    enabled.type = 'checkbox';
    enabled.checked = layer.enabled !== false;
    enabled.setAttribute('aria-label', `Enable slab layer ${index + 1}`);
    enabled.addEventListener('change', () => { layer.enabled = enabled.checked; });
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.textContent = '×';
    remove.setAttribute('aria-label', `Remove slab layer ${index + 1}`);
    remove.addEventListener('click', () => {
      currentSlabData.layers.splice(index, 1);
      renderLayerEditors();
    });
    row.append(name, thickness, material, enabled, remove);
    container.appendChild(row);
  });
}

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) window.sketchup.close_dialog();
}

function submitSlab() {
  const invalid = Array.from(document.querySelectorAll('input')).find(input => !input.checkValidity());
  if (invalid) {
    invalid.reportValidity();
    return;
  }
  currentSlabData.elevation = parseFloat(document.getElementById('slab-elevation').value) || 0;
  currentSlabData.reference = document.getElementById('slab-reference').value || 'top';
  if (window.sketchup && window.sketchup.create_or_update_slab) {
    window.sketchup.create_or_update_slab(JSON.stringify(currentSlabData));
  } else {
    window.alert('SketchUp is not connected to the slab settings dialog.');
  }
}
