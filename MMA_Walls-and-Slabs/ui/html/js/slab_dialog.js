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

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('slab-elevation').value = currentSlabData.elevation || 0;
  document.getElementById('slab-reference').value = currentSlabData.reference || 'top';
});

function closeDialog() {
  if (window.sketchup && window.sketchup.close_dialog) window.sketchup.close_dialog();
}

function submitSlab() {
  currentSlabData.elevation = parseFloat(document.getElementById('slab-elevation').value) || 0;
  currentSlabData.reference = document.getElementById('slab-reference').value || 'top';
  if (window.sketchup && window.sketchup.create_or_update_slab) {
    window.sketchup.create_or_update_slab(JSON.stringify(currentSlabData));
  }
}
