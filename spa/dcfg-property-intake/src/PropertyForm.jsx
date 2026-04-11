import React, { useState, useMemo } from 'react';
import { T } from './tokens.js';
import SegmentedControl from './SegmentedControl.jsx';

// ── Reusable field components ──
const TextField = ({ label, field, value, onChange, placeholder, hint }) => (
  <div style={{ marginBottom: 14 }}>
    <label style={{ fontSize: 12, fontWeight: 600, color: T.blue, display: 'block', marginBottom: 4 }}>{label}</label>
    <input value={value || ''} onChange={e => onChange(field, e.target.value)} placeholder={placeholder || ''}
      style={{ width: '100%', padding: '10px 12px', border: `1px solid ${T.border}`, borderRadius: 8, fontSize: 14, fontFamily: T.fBody, boxSizing: 'border-box' }} />
    {hint && <div style={{ fontSize: 11, color: T.textLight, marginTop: 3, fontStyle: 'italic' }}>{hint}</div>}
  </div>
);

const DetailPanel = ({ title, show, children }) => {
  if (!show) return null;
  return (
    <div style={{ background: T.bluePale, border: `1px solid ${T.blueMid}`, borderRadius: 8, padding: '14px 18px', marginTop: 8, marginBottom: 14 }}>
      {title && <div style={{ fontSize: 12, fontWeight: 700, color: T.blue, marginBottom: 10 }}>{title}</div>}
      {children}
    </div>
  );
};

const Grid = ({ cols = 2, children }) => (
  <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: '0 16px' }}>{children}</div>
);

const SectionIntro = ({ children }) => (
  <p style={{ fontSize: 13, color: '#64748B', lineHeight: 1.5, margin: '0 0 16px', padding: '0 0 12px', borderBottom: `1px solid ${T.border}` }}>
    {children}
  </p>
);

const SubHeading = ({ children }) => (
  <div style={{ fontSize: 12, fontWeight: 700, color: T.textLight, textTransform: 'uppercase', letterSpacing: 1, margin: '18px 0 10px' }}>{children}</div>
);

// Section definitions with customer-facing names and intros
const SECTIONS = [
  { id: 'identity', num: 1, title: 'About This Location', intro: "Let's confirm the basics. We've filled in what we know — update anything that's changed." },
  { id: 'contact', num: 2, title: 'Who Should We Contact?', intro: 'If we need to visit this location, who should we reach out to?' },
  { id: 'building', num: 3, title: 'Building Details', intro: 'Tell us about the structure. It\'s okay to skip anything you\'re not sure about.' },
  { id: 'features', num: 4, title: 'What\'s On Site?', intro: 'Quick yes/no questions about features at this location. If you\'re not at the building right now, you can come back to this later.' },
  { id: 'utilities', num: 5, title: 'Trash & Water', intro: 'How are trash and water handled at this location?' },
  { id: 'safety', num: 6, title: 'Fire & Safety', intro: 'Help us understand the fire safety setup. If you\'re not sure about counts, a rough estimate is fine.' },
  { id: 'inspections', num: 7, title: 'Inspections', intro: 'If this location has required inspections, when were they last done?' },
];

export default function PropertyForm({ property: p, onChange, onDelete, fieldConfig, locationTypes }) {
  const [activeSection, setActiveSection] = useState(0);
  const set = (field, value) => onChange(p.id, field, value);

  const isFieldVisible = (fieldKey) => {
    if (!fieldConfig || !p.homeType) return true;
    const entry = fieldConfig.find(c => c.key === fieldKey && c.locationType === p.homeType);
    if (!entry) return true;
    if (p._fieldOverrides && p._fieldOverrides[fieldKey] !== undefined) return p._fieldOverrides[fieldKey];
    return entry.visible;
  };

  // Calculate section completion (only count user-editable, visible fields)
  const sectionFields = useMemo(() => ({
    identity: ['streetAddress', 'city', 'state', 'zipCode', 'homeType', 'homeOwnership'],
    contact: ['contactPerson', 'contactPhone', 'contactEmail'],
    building: ['yearBuilt', 'bedrooms', 'stories'],
    features: ['lockBox', 'pool', 'generator', 'garage', 'septicSystem', 'solarPanels'],
    utilities: ['trashCollection', 'waterSupply'],
    safety: ['fireAlarmSystem'],
    inspections: ['lastIddInspection', 'lastDcaInspection'],
  }), []);

  const sectionProgress = (sectionId) => {
    const fields = sectionFields[sectionId] || [];
    if (fields.length === 0) return 100;
    const filled = fields.filter(f => p[f] && String(p[f]).trim()).length;
    return Math.round((filled / fields.length) * 100);
  };

  const sec = SECTIONS[activeSection];

  const typeOptions = locationTypes && locationTypes.length > 0
    ? locationTypes
    : ['Home', 'Apartment', 'Townhouse', 'Condo', 'Group Home', 'School'];

  return (
    <div style={{ maxWidth: 680, margin: '0 auto' }}>
      {/* Location header */}
      <div style={{ marginBottom: 20 }}>
        <h2 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 22, margin: '0 0 4px' }}>
          {p.upkeepName || p.streetAddress || 'New Location'}
        </h2>
        {p.streetAddress && (
          <div style={{ fontSize: 13, color: T.textLight }}>{p.streetAddress}{p.city ? `, ${p.city} ${p.state}` : ''}</div>
        )}
      </div>

      {/* Section map — clickable, shows progress */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 24, flexWrap: 'wrap' }}>
        {SECTIONS.map((s, i) => {
          const prog = sectionProgress(s.id);
          const isActive = i === activeSection;
          const isDone = prog === 100;
          return (
            <button key={s.id} onClick={() => setActiveSection(i)} style={{
              display: 'flex', alignItems: 'center', gap: 6,
              padding: '8px 14px', borderRadius: 8, fontSize: 12, fontWeight: 600, cursor: 'pointer',
              border: isActive ? `2px solid ${T.blueMid}` : `1px solid ${isDone ? T.green : T.border}`,
              background: isActive ? T.bluePale : isDone ? T.greenLt : 'white',
              color: isActive ? T.blue : isDone ? T.green : T.textLight,
              transition: 'all 0.15s',
            }}>
              {isDone ? '✓' : s.num}
              <span style={{ display: 'inline-block', maxWidth: 100, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {s.title}
              </span>
            </button>
          );
        })}
      </div>

      {/* Active section */}
      <div style={{ background: 'white', borderRadius: 12, padding: '28px 28px 20px', border: `1px solid ${T.border}`, minHeight: 300 }}>
        <h3 style={{ fontFamily: T.fDisplay, color: T.blue, fontSize: 18, margin: '0 0 8px' }}>
          {sec.title}
        </h3>
        <SectionIntro>{sec.intro}</SectionIntro>

        {/* ══ Section 1: About This Location ══ */}
        {activeSection === 0 && <>
          <Grid>
            <TextField label="Street Address" field="streetAddress" value={p.streetAddress} onChange={set} />
            <TextField label="City" field="city" value={p.city} onChange={set} />
            <TextField label="State" field="state" value={p.state} onChange={set} />
            <TextField label="Zip Code" field="zipCode" value={p.zipCode} onChange={set} />
          </Grid>
          <SegmentedControl label="What type of location is this?" options={typeOptions} value={p.homeType} onChange={v => set('homeType', v)} />
          <SegmentedControl label="Do you rent or own?" options={['Rent', 'Own']} value={p.homeOwnership} onChange={v => set('homeOwnership', v)} />
          {isFieldVisible('landlordInfo') && p.homeOwnership === 'Rent' && (
            <DetailPanel title="Landlord / Property Manager">
              <Grid>
                <TextField label="Name" field="landlordName" value={p.landlordName} onChange={set} />
                <TextField label="Phone" field="landlordPhone" value={p.landlordPhone} onChange={set} />
                <TextField label="Lease Start" field="leaseStart" value={p.leaseStart} onChange={set} hint="Approximate date is fine" />
                <TextField label="Lease End" field="leaseEnd" value={p.leaseEnd} onChange={set} />
              </Grid>
            </DetailPanel>
          )}
        </>}

        {/* ══ Section 2: Contact ══ */}
        {activeSection === 1 && <>
          <Grid>
            <TextField label="Name" field="contactPerson" value={p.contactPerson} onChange={set} hint="Who should we call about this location?" />
            <TextField label="Phone" field="contactPhone" value={p.contactPhone} onChange={set} />
            <TextField label="Email" field="contactEmail" value={p.contactEmail} onChange={set} />
            <TextField label="Best time to arrive" field="entryTime" value={p.entryTime} onChange={set} hint="e.g., After 9am, Before 3pm" />
          </Grid>
        </>}

        {/* ══ Section 3: Building Details ══ */}
        {activeSection === 2 && <>
          {isFieldVisible('structure') && <>
            <SubHeading>Structure</SubHeading>
            <Grid>
              <TextField label="Year Built" field="yearBuilt" value={p.yearBuilt} onChange={set} hint="Approximate is fine" />
              <TextField label="Number of residents / occupants" field="capacity" value={p.capacity} onChange={set} />
              <TextField label="Bedrooms" field="bedrooms" value={p.bedrooms} onChange={set} />
              <TextField label="Stories" field="stories" value={p.stories} onChange={set} />
            </Grid>
            <SegmentedControl label="Basement" options={['N/A', 'Finished', 'Unfinished']} value={p.basement} onChange={v => set('basement', v)} />
            <SegmentedControl label="Attic" options={['Y', 'N']} value={p.attic} onChange={v => set('attic', v)} />
          </>}
          {isFieldVisible('roofExterior') && <>
            <SubHeading>Roof & Exterior</SubHeading>
            <Grid>
              <TextField label="How old is the roof?" field="ageOfRoof" value={p.ageOfRoof} onChange={set} hint="e.g., 5 years, Not sure" />
              <TextField label="Roof material" field="typeOfRoof" value={p.typeOfRoof} onChange={set} hint="e.g., Asphalt shingles, Metal, Tile" />
            </Grid>
            <SegmentedControl label="Do you have roof warranty or inspection documents?" options={['Y', 'N']} value={p.roofDocumentation} onChange={v => set('roofDocumentation', v)} />
            <SegmentedControl label="Gutter guards installed?" options={['Y', 'N']} value={p.gutterGuards} onChange={v => set('gutterGuards', v)} />
          </>}
          {isFieldVisible('utilitiesAccess') && <>
            <SubHeading>Utilities & Access</SubHeading>
            <SegmentedControl label="Heating type" options={['Oil', 'Propane', 'Natural Gas']} value={p.heatingType} onChange={v => set('heatingType', v)} hint="How is the building heated?" />
            <SegmentedControl label="Floor plans available?" options={['Y', 'N']} value={p.floorPlansAvailable} onChange={v => set('floorPlansAvailable', v)} hint="Posted on walls, in a binder, digital — any format" />
            <SegmentedControl label="Parking" options={[{value:'Driveway',label:'Driveway'},{value:'Parking Lot',label:'Parking Lot'}]} value={p.parking} onChange={v => set('parking', v)} />
          </>}
        </>}

        {/* ══ Section 4: What's On Site? ══ */}
        {activeSection === 3 && <>
          {isFieldVisible('lockBox') && <>
            <SegmentedControl label="Is there a lock box for building access?" options={['Y', 'N']} value={p.lockBox} onChange={v => set('lockBox', v)} />
            {p.lockBox === 'Y' && (
              <DetailPanel>
                <Grid>
                  <TextField label="Lock box code" field="lockBoxCode" value={p.lockBoxCode} onChange={set} />
                  <TextField label="Where is it located?" field="lockBoxLocation" value={p.lockBoxLocation} onChange={set} hint="e.g., Front door, side entrance" />
                </Grid>
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('pool') && <>
            <SegmentedControl label="Pool on the property?" options={['Y', 'N']} value={p.pool} onChange={v => set('pool', v)} />
            {p.pool === 'Y' && (
              <DetailPanel>
                <SegmentedControl label="Type" options={['Above Ground', 'Inground']} value={p.poolType} onChange={v => set('poolType', v)} />
                <SegmentedControl label="Water" options={['Fresh', 'Salt']} value={p.poolWaterType} onChange={v => set('poolWaterType', v)} />
                <Grid>
                  <TextField label="Liner type" field="linerType" value={p.linerType} onChange={set} hint="If you know it" />
                  <TextField label="When was it installed?" field="poolInstallDate" value={p.poolInstallDate} onChange={set} />
                  <TextField label="Pump model" field="pumpModel" value={p.pumpModel} onChange={set} hint="Check the nameplate if you're on site" />
                </Grid>
                <TextField label="Anything else about the pool?" field="poolNotes" value={p.poolNotes} onChange={set} />
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('generator') && <>
            <SegmentedControl label="Generator?" options={['Y', 'N']} value={p.generator} onChange={v => set('generator', v)} />
            {p.generator === 'Y' && (
              <DetailPanel>
                <SegmentedControl label="Fuel type" options={['Oil', 'Propane', 'Natural Gas']} value={p.genFuelType} onChange={v => set('genFuelType', v)} />
                <Grid>
                  <TextField label="Make" field="genMake" value={p.genMake} onChange={set} hint="Check the nameplate — or snap a photo" />
                  <TextField label="Model" field="genModel" value={p.genModel} onChange={set} />
                  <TextField label="Serial number" field="genSerial" value={p.genSerial} onChange={set} />
                  <TextField label="Who services it?" field="genServiceProvider" value={p.genServiceProvider} onChange={set} />
                </Grid>
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('garage') && <>
            <SegmentedControl label="Garage?" options={['Y', 'N']} value={p.garage} onChange={v => set('garage', v)} />
            {p.garage === 'Y' && (
              <DetailPanel>
                <SegmentedControl label="Size" options={['1 Car', '2 Car', '3 Car']} value={p.garageSize} onChange={v => set('garageSize', v)} />
                <SegmentedControl label="Attached to building?" options={['Y', 'N']} value={p.garageAttached} onChange={v => set('garageAttached', v)} />
                <SegmentedControl label="Finished inside?" options={['Y', 'N']} value={p.garageFinished} onChange={v => set('garageFinished', v)} />
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('septicSystem') && <>
            <SegmentedControl label="Septic system?" options={['Y', 'N']} value={p.septicSystem} onChange={v => set('septicSystem', v)} />
            {p.septicSystem === 'Y' && (
              <DetailPanel>
                <SegmentedControl label="Advanced treatment unit (ATU)?" options={['Y', 'N']} value={p.septicAtu} onChange={v => set('septicAtu', v)} hint="If you're not sure, that's okay — just leave it blank" />
                <Grid>
                  <TextField label="Tank capacity" field="septicCapacity" value={p.septicCapacity} onChange={set} hint="e.g., 1000 gallons" />
                  <TextField label="When was it installed?" field="septicInstallDate" value={p.septicInstallDate} onChange={set} />
                </Grid>
                <SegmentedControl label="Drawings or diagrams available?" options={['Y', 'N']} value={p.septicDrawings} onChange={v => set('septicDrawings', v)} />
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('solarPanels') && <>
            <SegmentedControl label="Solar panels?" options={['Y', 'N']} value={p.solarPanels} onChange={v => set('solarPanels', v)} />
            {p.solarPanels === 'Y' && (
              <DetailPanel>
                <Grid>
                  <TextField label="System size (kW)" field="solarSize" value={p.solarSize} onChange={set} hint="Check your electric bill or installer docs" />
                  <TextField label="Installer" field="solarInstaller" value={p.solarInstaller} onChange={set} />
                  <TextField label="Install date" field="solarInstallDate" value={p.solarInstallDate} onChange={set} />
                </Grid>
                <SegmentedControl label="Leased or owned?" options={['Lease', 'Owned']} value={p.solarLeaseOwned} onChange={v => set('solarLeaseOwned', v)} />
                <Grid>
                  <TextField label="Monitoring provider" field="solarMonitoring" value={p.solarMonitoring} onChange={set} />
                  <TextField label="Annual output (kWh)" field="solarOutput" value={p.solarOutput} onChange={set} />
                </Grid>
                <TextField label="Notes" field="solarNotes" value={p.solarNotes} onChange={set} />
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('fireSafetySprinkler') && (
            <SegmentedControl label="Fire safety sprinklers?" options={['Y', 'N']} value={p.fireSafetySprinkler} onChange={v => set('fireSafetySprinkler', v)} />
          )}
          {isFieldVisible('detectorsHardwired') && (
            <SegmentedControl label="Are smoke/CO detectors hardwired?" options={['Y', 'N']} value={p.detectorsHardwired} onChange={v => set('detectorsHardwired', v)} />
          )}
          {isFieldVisible('waterTreatment') && (
            <SegmentedControl label="Water treatment system?" options={['Y', 'N']} value={p.waterTreatmentSystem} onChange={v => set('waterTreatmentSystem', v)} />
          )}
          {isFieldVisible('wellWater') && (
            <SegmentedControl label="Well water?" options={['Y', 'N']} value={p.wellWater} onChange={v => set('wellWater', v)} />
          )}
        </>}

        {/* ══ Section 5: Trash & Water ══ */}
        {activeSection === 4 && <>
          {isFieldVisible('trashCollection') && <>
            <SegmentedControl label="How is trash collected?" options={[{value:'Township',label:'City / Township'},{value:'Contract',label:'Private company'}]} value={p.trashCollection} onChange={v => set('trashCollection', v)} />
            {p.trashCollection === 'Township' && (
              <DetailPanel>
                <Grid>
                  <TextField label="How many trash cans?" field="trashCans" value={p.trashCans} onChange={set} />
                  <TextField label="Maximum allowed?" field="maxTrashCans" value={p.maxTrashCans} onChange={set} hint="If you know it" />
                  <TextField label="Recycling cans?" field="recyclingCans" value={p.recyclingCans} onChange={set} />
                  <TextField label="Maximum recycling?" field="maxRecyclingCans" value={p.maxRecyclingCans} onChange={set} />
                </Grid>
              </DetailPanel>
            )}
            {p.trashCollection === 'Contract' && (
              <DetailPanel>
                <Grid>
                  <TextField label="Company name" field="trashVendor" value={p.trashVendor} onChange={set} />
                  <TextField label="Monthly cost" field="trashMonthlyCost" value={p.trashMonthlyCost} onChange={set} hint="Approximate is fine" />
                  <TextField label="Contract start" field="trashContractStart" value={p.trashContractStart} onChange={set} />
                  <TextField label="Contract end" field="trashContractEnd" value={p.trashContractEnd} onChange={set} />
                </Grid>
                <SegmentedControl label="Do they handle recycling too?" options={['Y', 'N']} value={p.trashHandlesRecycling} onChange={v => set('trashHandlesRecycling', v)} />
              </DetailPanel>
            )}
          </>}
          {isFieldVisible('waterSupply') && <>
            <SegmentedControl label="Water source" options={[{value:'Well',label:'Well'},{value:'City',label:'City / Municipal'}]} value={p.waterSupply} onChange={v => set('waterSupply', v)} />
            {p.waterSupply === 'Well' && (
              <DetailPanel>
                <SegmentedControl label="Certified in the last 5 years?" options={['Y', 'N']} value={p.wellCertified} onChange={v => set('wellCertified', v)} />
                <SegmentedControl label="Do you have the certification documents?" options={['Y', 'N']} value={p.wellDocumentation} onChange={v => set('wellDocumentation', v)} />
              </DetailPanel>
            )}
          </>}
        </>}

        {/* ══ Section 6: Fire & Safety ══ */}
        {activeSection === 5 && <>
          {isFieldVisible('fireAlarmSystem') && <>
            <SegmentedControl label="What kind of fire alarm system?" options={[
              {value:'Localized',label:'Local alarms only'},
              {value:'Monitored',label:'Professionally monitored'},
              {value:'Both',label:'Both'},
            ]} value={p.fireAlarmSystem} onChange={v => set('fireAlarmSystem', v)} />
            {p.fireAlarmSystem && p.fireAlarmSystem !== '' && (
              <DetailPanel>
                <SegmentedControl label="Fire sprinklers?" options={['Y', 'N']} value={p.fireAlarmSprinkler} onChange={v => set('fireAlarmSprinkler', v)} />
                <SegmentedControl label="Alarm monitoring service?" options={['Y', 'N']} value={p.fireAlarmMonitoring} onChange={v => set('fireAlarmMonitoring', v)} />
                <Grid>
                  <TextField label="Fire extinguishers" field="fireExtinguishers" value={p.fireExtinguishers} onChange={set} hint="How many? A rough count is fine" />
                  <TextField label="CO detectors" field="coDetectors" value={p.coDetectors} onChange={set} hint="Rough count" />
                  <TextField label="Smoke detectors" field="smokeDetectors" value={p.smokeDetectors} onChange={set} hint="Rough count" />
                  <TextField label="Last system inspection" field="annualInspection" value={p.annualInspection} onChange={set} hint="Date or year, if you know it" />
                </Grid>
                <SegmentedControl label="Door chimes in the building?" options={['Y', 'N']} value={p.chimesInHome} onChange={v => set('chimesInHome', v)} />
              </DetailPanel>
            )}
          </>}
        </>}

        {/* ══ Section 7: Inspections ══ */}
        {activeSection === 6 && <>
          <Grid>
            {isFieldVisible('iddInspection') && (
              <TextField label="Last IDD inspection" field="lastIddInspection" value={p.lastIddInspection} onChange={set}
                hint="Intellectual/Developmental Disabilities — date or year" />
            )}
            {isFieldVisible('dcaInspection') && (
              <TextField label="Last DCA inspection" field="lastDcaInspection" value={p.lastDcaInspection} onChange={set}
                hint="Dept. of Community Affairs — date or year" />
            )}
          </Grid>
        </>}
      </div>

      {/* Navigation */}
      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 16 }}>
        <button
          onClick={() => setActiveSection(Math.max(0, activeSection - 1))}
          disabled={activeSection === 0}
          style={{
            padding: '10px 20px', borderRadius: 8, fontSize: 14, fontWeight: 600, cursor: activeSection === 0 ? 'default' : 'pointer',
            background: 'white', border: `1px solid ${T.border}`, color: activeSection === 0 ? T.textLight : T.blue,
            opacity: activeSection === 0 ? 0.4 : 1,
          }}
        >
          ← Back
        </button>
        {activeSection < SECTIONS.length - 1 ? (
          <button
            onClick={() => setActiveSection(activeSection + 1)}
            style={{
              padding: '10px 24px', borderRadius: 8, fontSize: 14, fontWeight: 600, cursor: 'pointer',
              background: T.blue, border: 'none', color: 'white',
            }}
          >
            Next →
          </button>
        ) : (
          <div style={{
            padding: '10px 24px', borderRadius: 8, fontSize: 14, fontWeight: 600,
            background: sectionProgress('inspections') === 100 ? T.greenLt : T.bg,
            color: sectionProgress('inspections') === 100 ? T.green : T.textLight,
            border: `1px solid ${sectionProgress('inspections') === 100 ? T.green : T.border}`,
          }}>
            {sectionProgress('inspections') === 100 ? '✓ All sections visited' : 'Last section'}
          </div>
        )}
      </div>
    </div>
  );
}
