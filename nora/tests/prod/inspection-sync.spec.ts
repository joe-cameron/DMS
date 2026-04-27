/**
 * Inspection Sync Agent — UpKeep → Dataverse
 *
 * Pulls inspection WO date changes from UpKeep and updates the
 * dcfg_inspection_assignment records in Dataverse to keep the
 * plan aligned with reality.
 *
 * Run on a routine: /loop 30m /nora or via cron
 *
 * UpKeep is READ-ONLY — we only read from it.
 * Dataverse assignments get updated when UpKeep dates shift.
 */
import { test } from '@playwright/test';

const UPKEEP_EMAIL = 'service@decades-cg.com';
const UPKEEP_PASSWORD = 'UpKeep123!';
const UPKEEP_API = 'https://api.onupkeep.com/api/v2';

interface UpKeepWO {
  id: string;
  title: string;
  status: string;
  category: string;
  dueDate: string;
  createdAt: string;
  locationName: string;
  location: string;
}

interface SyncResult {
  timestamp: string;
  upkeep_inspections_found: number;
  date_changes_detected: number;
  new_wos_detected: number;
  completed_since_last: number;
  changes: Array<{
    wo_id: string;
    title: string;
    field: string;
    old_value: string;
    new_value: string;
  }>;
  status: 'clean' | 'changes_detected' | 'error';
  error?: string;
}

test('inspection-sync: pull UpKeep changes and update plan', async ({ request }) => {
  const result: SyncResult = {
    timestamp: new Date().toISOString(),
    upkeep_inspections_found: 0,
    date_changes_detected: 0,
    new_wos_detected: 0,
    completed_since_last: 0,
    changes: [],
    status: 'clean'
  };

  // 1. Read last sync state
  const fs = await import('fs');
  const path = await import('path');
  const stateFile = path.join(__dirname, '../../test-results/inspection-sync-state.json');
  let lastState: Record<string, { dueDate: string; status: string }> = {};
  try {
    const raw = fs.readFileSync(stateFile, 'utf8');
    lastState = JSON.parse(raw);
  } catch {
    // First run — no prior state
  }

  // 2. Auth to UpKeep
  const authResp = await request.post(`${UPKEEP_API}/auth`, {
    data: { email: UPKEEP_EMAIL, password: UPKEEP_PASSWORD }
  });
  const authData = await authResp.json();
  const sessionToken = authData.result.sessionToken;
  const headers = { 'Session-Token': sessionToken };

  // 3. Pull all inspection WOs (paginated)
  const allWOs: UpKeepWO[] = [];
  let page = 0;
  let hasMore = true;
  while (hasMore) {
    const resp = await request.get(`${UPKEEP_API}/work-orders`, {
      headers,
      params: { limit: '200', offset: String(page * 200) }
    });
    const data = await resp.json();
    const inspections = (data.results || []).filter((w: any) =>
      w.title?.match(/insp/i) || w.category?.match(/inspect/i)
    );
    allWOs.push(...inspections);
    hasMore = data.results?.length === 200;
    page++;
    if (page > 20) break; // safety
  }
  result.upkeep_inspections_found = allWOs.length;

  // 4. Compare against last state — detect changes
  const newState: Record<string, { dueDate: string; status: string }> = {};

  for (const wo of allWOs) {
    newState[wo.id] = { dueDate: wo.dueDate || '', status: wo.status || '' };

    const prev = lastState[wo.id];
    if (!prev) {
      // New WO since last sync
      result.new_wos_detected++;
      result.changes.push({
        wo_id: wo.id,
        title: wo.title,
        field: 'new_wo',
        old_value: '',
        new_value: `due=${wo.dueDate} status=${wo.status}`
      });
      continue;
    }

    // Check date change
    if (prev.dueDate !== (wo.dueDate || '')) {
      result.date_changes_detected++;
      result.changes.push({
        wo_id: wo.id,
        title: wo.title,
        field: 'dueDate',
        old_value: prev.dueDate,
        new_value: wo.dueDate || ''
      });
    }

    // Check status change (especially completions)
    if (prev.status !== wo.status) {
      if (wo.status === 'complete') result.completed_since_last++;
      result.changes.push({
        wo_id: wo.id,
        title: wo.title,
        field: 'status',
        old_value: prev.status,
        new_value: wo.status
      });
    }
  }

  // 5. Write changes to Dataverse dcfg_im_schedule
  if (result.changes.length > 0) {
    // Auth to Dataverse via pac
    const { execSync } = await import('child_process');
    let dvToken = '';
    try {
      const tokenOut = execSync('pac auth token --environment https://org06f5de0b.crm.dynamics.com', { encoding: 'utf8', timeout: 30000 });
      dvToken = tokenOut.trim();
    } catch {
      // Fallback: try pac org who to confirm connection, then use token from env
      console.log('[inspection-sync] pac auth token failed, trying direct auth...');
    }

    const DV_URL = 'https://org06f5de0b.api.crm.dynamics.com/api/data/v9.2';
    const dvHeaders = {
      'Authorization': 'Bearer ' + dvToken,
      'Content-Type': 'application/json',
      'OData-MaxVersion': '4.0',
      'OData-Version': '4.0',
      'MSCRM.SolutionUniqueName': 'DCFGSystemTest',
    };

    if (dvToken) {
      // Build lookup: upkeep_wo_id → dcfg_im_schedule record
      const existingResp = await request.get(`${DV_URL}/dcfg_im_schedules?$select=dcfg_im_scheduleid,dcfg_upkeep_wo_id,dcfg_visit_status,dcfg_scheduled_date&$filter=dcfg_active_flag eq true&$top=5000`, {
        headers: { ...dvHeaders, 'Content-Type': undefined } as any,
      });
      const existingData = await existingResp.json();
      const byWoId: Record<string, any> = {};
      for (const rec of (existingData.value || [])) {
        if (rec.dcfg_upkeep_wo_id) byWoId[rec.dcfg_upkeep_wo_id] = rec;
      }

      let created = 0, updated = 0, errors = 0;

      for (const change of result.changes) {
        const wo = allWOs.find(w => w.id === change.wo_id);
        if (!wo) continue;

        const existing = byWoId[wo.id];

        // Map UpKeep status to dcfg_visit_status picklist
        let visitStatus = 100000000; // Scheduled
        if (wo.status === 'complete') visitStatus = 100000001; // Complete
        else if (wo.status === 'onHold' || wo.status === 'overdue') visitStatus = 100000002; // Overdue

        if (existing) {
          // Update existing record
          try {
            const patchBody: any = {
              dcfg_visit_status: visitStatus,
            };
            if (wo.dueDate) patchBody.dcfg_scheduled_date = wo.dueDate;
            if (wo.status === 'complete') patchBody.dcfg_completed_date = new Date().toISOString();

            await request.patch(`${DV_URL}/dcfg_im_schedules(${existing.dcfg_im_scheduleid})`, {
              headers: dvHeaders,
              data: patchBody,
            });
            updated++;
          } catch (e: any) {
            console.log(`[inspection-sync] Failed to update ${wo.id}: ${e.message}`);
            errors++;
          }
        } else if (change.field === 'new_wo') {
          // Create new record
          try {
            const isInspection = wo.title?.match(/insp/i) || wo.category?.match(/inspect/i);
            const createBody: any = {
              dcfg_name: wo.title || 'Inspection WO ' + wo.id,
              dcfg_upkeep_wo_id: wo.id,
              dcfg_visit_status: visitStatus,
              dcfg_active_flag: true,
              dcfg_is_first_inspection: false,
              dcfg_category: isInspection ? 'Inspection' : (wo.category || 'Other'),
            };
            if (wo.dueDate) createBody.dcfg_scheduled_date = wo.dueDate;
            if (wo.status === 'complete') createBody.dcfg_completed_date = new Date().toISOString();

            // Try to match location to a property
            if (wo.location) {
              // Look up property by upkeep_location_id
              const propResp = await request.get(`${DV_URL}/dcfg_properties?$select=dcfg_propertyid&$filter=dcfg_upkeep_location_id eq '${wo.location}'&$top=1`, {
                headers: { ...dvHeaders, 'Content-Type': undefined } as any,
              });
              const propData = await propResp.json();
              if (propData.value && propData.value.length > 0) {
                createBody['dcfg_property_id@odata.bind'] = `/dcfg_properties(${propData.value[0].dcfg_propertyid})`;
              }
            }

            await request.post(`${DV_URL}/dcfg_im_schedules`, {
              headers: dvHeaders,
              data: createBody,
            });
            created++;
          } catch (e: any) {
            console.log(`[inspection-sync] Failed to create ${wo.id}: ${e.message}`);
            errors++;
          }
        }
      }

      console.log(`[inspection-sync] Dataverse sync: ${created} created, ${updated} updated, ${errors} errors`);
      (result as any).dv_created = created;
      (result as any).dv_updated = updated;
      (result as any).dv_errors = errors;
    } else {
      console.log('[inspection-sync] No Dataverse token — skipping write. Changes logged locally only.');
    }
  }

  // 5b. Save new state
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify(newState, null, 2));

  // 6. Write sync result
  if (result.changes.length > 0) {
    result.status = 'changes_detected';
  }

  const resultFile = path.join(__dirname, '../../test-results/inspection-sync-result.json');
  fs.writeFileSync(resultFile, JSON.stringify(result, null, 2));

  // 7. Write changes log (append)
  if (result.changes.length > 0) {
    const logFile = path.join(__dirname, '../../test-results/inspection-sync-log.jsonl');
    const logEntry = JSON.stringify({
      timestamp: result.timestamp,
      changes: result.changes
    });
    fs.appendFileSync(logFile, logEntry + '\n');
  }

  // 8. Console output for monitoring
  if (result.changes.length === 0) {
    console.log(`[inspection-sync] ${result.timestamp} — clean. ${result.upkeep_inspections_found} WOs checked, no changes.`);
  } else {
    console.log(`[inspection-sync] ${result.timestamp} — CHANGES DETECTED:`);
    console.log(`  Date changes: ${result.date_changes_detected}`);
    console.log(`  New WOs: ${result.new_wos_detected}`);
    console.log(`  Completions: ${result.completed_since_last}`);
    for (const c of result.changes) {
      console.log(`  ${c.field}: ${c.title} | ${c.old_value} → ${c.new_value}`);
    }
  }
});
