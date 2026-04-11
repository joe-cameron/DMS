/**
 * storage.js — localStorage persistence layer
 * Key: provider:{accessCode}
 * Value: { properties: [...], vendors: [...], lastModified: ISO8601 }
 */

const PREFIX = 'provider:';

export function loadProviderData(code) {
  try {
    const raw = localStorage.getItem(PREFIX + code);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch { return null; }
}

export function saveProviderData(code, data) {
  try {
    data.lastModified = new Date().toISOString();
    localStorage.setItem(PREFIX + code, JSON.stringify(data));
  } catch (e) {
    console.warn('Storage save failed:', e.message);
  }
}

export function createEmptyProvider() {
  const expires = new Date();
  expires.setDate(expires.getDate() + 30);
  return {
    properties: [],
    vendors: [],
    authorizedUsers: [],
    expiresAt: expires.toISOString(),
    lastModified: new Date().toISOString(),
  };
}

export function createEmptyUser() {
  return {
    id: crypto.randomUUID(),
    email: '',
    name: '',
    phone: '',
    accessLevel: 'all',
    locationIds: [],
  };
}

export function createEmptyProperty() {
  return {
    id: crypto.randomUUID(),
    // UpKeep source data (populated by seed, read-only display)
    upkeepLocationId: '', upkeepParentId: '', upkeepName: '',
    // Location Identity
    streetAddress: '', city: '', state: '', zipCode: '',
    homeType: '', homeOwnership: '', serviceLine: '',
    // Site Contact
    contactPerson: '', contactPhone: '', contactEmail: '', entryTime: '',
    // Home Details
    yearBuilt: '', capacity: '', bedrooms: '', stories: '',
    basement: '', attic: '', ageOfRoof: '', typeOfRoof: '',
    roofDocumentation: '', gutterGuards: '', heatingType: '',
    floorPlansAvailable: '', parking: '',
    // Features & Systems (Y/N triggers)
    lockBox: '', pool: '', generator: '', garage: '',
    septicSystem: '', solarPanels: '', fireAlarmSystem: '',
    detectorsHardwired: '', fireSafetySprinkler: '',
    waterTreatmentSystem: '', wellWater: '', waterSupply: '',
    // Trash & Utilities
    trashCollection: '',
    // Inspections
    lastIddInspection: '', lastDcaInspection: '',
    // ── Child detail fields ──
    // LockBox
    lockBoxCode: '', lockBoxLocation: '',
    // Landlord
    landlordName: '', landlordPhone: '', leaseStart: '', leaseEnd: '', leaseDocLink: '',
    // Pool
    poolType: '', poolWaterType: '', linerType: '', poolInstallDate: '', pumpModel: '', poolNotes: '',
    // Generator
    genFuelType: '', genMake: '', genModel: '', genSerial: '', genServiceProvider: '',
    // Garage
    garageSize: '', garageAttached: '', garageFinished: '',
    // Township Trash
    trashCans: '', maxTrashCans: '', recyclingCans: '', maxRecyclingCans: '',
    // Contract Trash
    trashVendor: '', trashHandlesRecycling: '', trashContractStart: '', trashContractEnd: '', trashMonthlyCost: '',
    // Solar
    solarSize: '', solarInstaller: '', solarInstallDate: '', solarLeaseOwned: '',
    solarMonitoring: '', solarOutput: '', solarNotes: '',
    // Septic
    septicAtu: '', septicCapacity: '', septicInstallDate: '', septicDrawings: '',
    // Well Water
    wellCertified: '', wellDocumentation: '',
    // Fire Alarm
    fireAlarmSprinkler: '', fireAlarmMonitoring: '', fireExtinguishers: '',
    coDetectors: '', smokeDetectors: '', annualInspection: '', chimesInHome: '',
  };
}

export function createEmptyVendor() {
  return {
    id: crypto.randomUUID(),
    vendorName: '', serviceProvided: '', contactName: '',
    contactPhone: '', contactEmail: '',
    contractStart: '', contractEnd: '', requiresReBid: '',
  };
}

/** Map form field keys (camelCase) to Dataverse column names */
export const FIELD_MAP = {
  streetAddress: 'dcfg_street_address',
  city: 'dcfg_city',
  state: 'dcfg_state',
  zipCode: 'dcfg_zip_code',
  homeType: 'dcfg_home_type',
  homeOwnership: 'dcfg_home_ownership',
  serviceLine: 'dcfg_service_line',
  landlordName: 'dcfg_landlord_name',
  landlordPhone: 'dcfg_landlord_phone',
  leaseStart: 'dcfg_lease_start',
  leaseEnd: 'dcfg_lease_end',
  leaseDocLink: 'dcfg_lease_doc_link',
  contactPerson: 'dcfg_contact_person',
  contactPhone: 'dcfg_contact_phone',
  contactEmail: 'dcfg_contact_email',
  entryTime: 'dcfg_entry_time',
  yearBuilt: 'dcfg_year_built',
  capacity: 'dcfg_capacity',
  bedrooms: 'dcfg_bedrooms',
  stories: 'dcfg_stories',
  basement: 'dcfg_basement',
  attic: 'dcfg_attic',
  ageOfRoof: 'dcfg_age_of_roof',
  typeOfRoof: 'dcfg_type_of_roof',
  roofDocumentation: 'dcfg_roof_documentation',
  gutterGuards: 'dcfg_gutter_guards',
  heatingType: 'dcfg_heating_type',
  floorPlansAvailable: 'dcfg_floor_plans',
  parking: 'dcfg_parking',
  lockBox: 'dcfg_lock_box',
  lockBoxCode: 'dcfg_lock_box_code',
  lockBoxLocation: 'dcfg_lock_box_location',
  pool: 'dcfg_pool',
  poolType: 'dcfg_pool_type',
  poolWaterType: 'dcfg_pool_water_type',
  linerType: 'dcfg_liner_type',
  poolInstallDate: 'dcfg_pool_install_date',
  pumpModel: 'dcfg_pump_model',
  poolNotes: 'dcfg_pool_notes',
  generator: 'dcfg_generator',
  genFuelType: 'dcfg_gen_fuel_type',
  genMake: 'dcfg_gen_make',
  genModel: 'dcfg_gen_model',
  genSerial: 'dcfg_gen_serial',
  genServiceProvider: 'dcfg_gen_service_provider',
  garage: 'dcfg_garage',
  garageSize: 'dcfg_garage_size',
  garageAttached: 'dcfg_garage_attached',
  garageFinished: 'dcfg_garage_finished',
  septicSystem: 'dcfg_septic_system',
  septicAtu: 'dcfg_septic_atu',
  septicCapacity: 'dcfg_septic_capacity',
  septicInstallDate: 'dcfg_septic_install_date',
  septicDrawings: 'dcfg_septic_drawings',
  solarPanels: 'dcfg_solar_panels',
  solarSize: 'dcfg_solar_size',
  solarInstaller: 'dcfg_solar_installer',
  solarInstallDate: 'dcfg_solar_install_date',
  solarLeaseOwned: 'dcfg_solar_lease_owned',
  solarMonitoring: 'dcfg_solar_monitoring',
  solarOutput: 'dcfg_solar_output',
  solarNotes: 'dcfg_solar_notes',
  fireSafetySprinkler: 'dcfg_fire_safety_sprinkler',
  detectorsHardwired: 'dcfg_detectors_hardwired',
  waterTreatmentSystem: 'dcfg_water_treatment',
  wellWater: 'dcfg_well_water',
  trashCollection: 'dcfg_trash_collection',
  trashCans: 'dcfg_trash_cans',
  maxTrashCans: 'dcfg_max_trash_cans',
  recyclingCans: 'dcfg_recycling_cans',
  maxRecyclingCans: 'dcfg_max_recycling_cans',
  trashVendor: 'dcfg_trash_vendor',
  trashHandlesRecycling: 'dcfg_trash_handles_recycling',
  trashContractStart: 'dcfg_trash_contract_start',
  trashContractEnd: 'dcfg_trash_contract_end',
  trashMonthlyCost: 'dcfg_trash_monthly_cost',
  waterSupply: 'dcfg_water_supply',
  wellCertified: 'dcfg_well_certified',
  wellDocumentation: 'dcfg_well_documentation',
  fireAlarmSystem: 'dcfg_fire_alarm_system',
  fireAlarmSprinkler: 'dcfg_fire_alarm_sprinkler',
  fireAlarmMonitoring: 'dcfg_fire_alarm_monitoring',
  fireExtinguishers: 'dcfg_fire_extinguishers',
  coDetectors: 'dcfg_co_detectors',
  smokeDetectors: 'dcfg_smoke_detectors',
  annualInspection: 'dcfg_annual_inspection',
  chimesInHome: 'dcfg_chimes_in_home',
  lastIddInspection: 'dcfg_last_idd_inspection',
  lastDcaInspection: 'dcfg_last_dca_inspection',
};

export const REVERSE_FIELD_MAP = Object.fromEntries(
  Object.entries(FIELD_MAP).map(([k, v]) => [v, k])
);

export function dataverseToForm(dvRecord) {
  const prop = createEmptyProperty();
  prop.id = dvRecord.dcfg_property_intakeid || prop.id;
  prop._dataverseId = dvRecord.dcfg_property_intakeid;
  prop.upkeepLocationId = dvRecord.dcfg_upkeep_location_id || '';
  prop.upkeepParentId = dvRecord.dcfg_upkeep_parent_id || '';
  prop.upkeepName = dvRecord.dcfg_upkeep_name || '';
  for (const [formKey, dvKey] of Object.entries(FIELD_MAP)) {
    if (dvRecord[dvKey] !== undefined && dvRecord[dvKey] !== null) {
      prop[formKey] = dvRecord[dvKey];
    }
  }
  if (dvRecord.dcfg_field_overrides) {
    try { prop._fieldOverrides = JSON.parse(dvRecord.dcfg_field_overrides); } catch {}
  }
  return prop;
}

export function formFieldToDataverse(fieldName) {
  return FIELD_MAP[fieldName] || null;
}
