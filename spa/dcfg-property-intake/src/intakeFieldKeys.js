/**
 * Intake form field keys — shared registry for config matrix and form rendering.
 * Each key maps to a configurable row in the admin Intake Fields matrix.
 * Sections 1 (Location Identity) and 2 (Site Contact) are always shown.
 */
export const INTAKE_FIELD_KEYS = [
  // Section 3: Home Details
  { key: 'structure',       section: 'Home Details',       label: 'Structure',              sectionNum: 3 },
  { key: 'roofExterior',    section: 'Home Details',       label: 'Roof & Exterior',        sectionNum: 3 },
  { key: 'utilitiesAccess', section: 'Home Details',       label: 'Utilities & Access',     sectionNum: 3 },
  // Section 4: Features & Systems
  { key: 'lockBox',         section: 'Features & Systems', label: 'Lock Box',               sectionNum: 4 },
  { key: 'pool',            section: 'Features & Systems', label: 'Pool',                   sectionNum: 4 },
  { key: 'generator',       section: 'Features & Systems', label: 'Generator',              sectionNum: 4 },
  { key: 'garage',          section: 'Features & Systems', label: 'Garage',                 sectionNum: 4 },
  { key: 'septicSystem',    section: 'Features & Systems', label: 'Septic System',          sectionNum: 4 },
  { key: 'solarPanels',     section: 'Features & Systems', label: 'Solar Panels',           sectionNum: 4 },
  { key: 'fireSafetySprinkler', section: 'Features & Systems', label: 'Fire Safety Sprinkler', sectionNum: 4 },
  { key: 'detectorsHardwired',  section: 'Features & Systems', label: 'Hardwired Detectors',   sectionNum: 4 },
  { key: 'waterTreatment',  section: 'Features & Systems', label: 'Water Treatment',        sectionNum: 4 },
  { key: 'wellWater',       section: 'Features & Systems', label: 'Well Water',             sectionNum: 4 },
  // Section 5: Trash & Utilities
  { key: 'trashCollection', section: 'Trash & Utilities',  label: 'Trash Collection',       sectionNum: 5 },
  { key: 'waterSupply',     section: 'Trash & Utilities',  label: 'Water Supply',           sectionNum: 5 },
  // Section 6: Fire & Safety
  { key: 'fireAlarmSystem', section: 'Fire & Safety',      label: 'Fire Alarm System',      sectionNum: 6 },
  // Section 7: Inspections
  { key: 'iddInspection',   section: 'Inspections',        label: 'IDD Inspection',         sectionNum: 7 },
  { key: 'dcaInspection',   section: 'Inspections',        label: 'DCA Inspection',         sectionNum: 7 },
  // Section 1 conditional
  { key: 'landlordInfo',    section: 'Location Identity',  label: 'Landlord Info',          sectionNum: 1 },
];

/** Group field keys by section for rendering */
export function groupBySection() {
  const groups = [];
  let current = null;
  for (const f of INTAKE_FIELD_KEYS) {
    if (!current || current.section !== f.section) {
      current = { section: f.section, sectionNum: f.sectionNum, fields: [] };
      groups.push(current);
    }
    current.fields.push(f);
  }
  return groups;
}
