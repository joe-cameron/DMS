const { app } = require('@azure/functions');

/**
 * inspectionSync — Timer-triggered Azure Function
 *
 * Pulls inspection WOs from BOTH UpKeep accounts, compares against
 * Dataverse dcfg_im_schedule, writes new/changed records. Runs every 30 minutes.
 *
 * Environment variables:
 *   UPKEEP_EMAIL            — Multi-site UpKeep login (PennReach, J-ADD, Arc Mercer, PCDI, Newgrange)
 *   UPKEEP_PASSWORD         — Multi-site UpKeep password
 *   UPKEEP_EMAIL_2          — Second UpKeep account login (Bancroft)
 *   UPKEEP_PASSWORD_2       — Second UpKeep account password
 *   DATAVERSE_URL           — e.g. https://org06f5de0b.api.crm.dynamics.com
 *   DATAVERSE_TENANT_ID     — Azure AD tenant
 *   DATAVERSE_CLIENT_ID     — App registration client ID
 *   DATAVERSE_CLIENT_SECRET — App registration client secret
 */

const UPKEEP_API = 'https://api.onupkeep.com/api/v2';

// ── UpKeep Auth ──────────────────────────────────────
async function getUpKeepToken(email, password) {
    const resp = await fetch(UPKEEP_API + '/auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
    });
    const data = await resp.json();
    if (!data.result || !data.result.sessionToken) {
        throw new Error('UpKeep auth failed: ' + JSON.stringify(data));
    }
    return data.result.sessionToken;
}

// ── Dataverse Auth (client credentials) ──────────────
async function getDataverseToken(tenantId, clientId, clientSecret, dvUrl) {
    const scope = dvUrl.replace('/api/data/v9.2', '') + '/.default';
    const tokenUrl = 'https://login.microsoftonline.com/' + tenantId + '/oauth2/v2.0/token';
    const body = new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: clientId,
        client_secret: clientSecret,
        scope: scope,
    });
    const resp = await fetch(tokenUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
    });
    const data = await resp.json();
    if (!data.access_token) {
        throw new Error('Dataverse auth failed: ' + JSON.stringify(data));
    }
    return data.access_token;
}

// ── Pull UpKeep Inspection WOs ───────────────────────
async function pullUpKeepInspections(sessionToken) {
    const headers = { 'Session-Token': sessionToken };
    var allWOs = [];
    var page = 0;
    var hasMore = true;

    while (hasMore) {
        const resp = await fetch(UPKEEP_API + '/work-orders?limit=200&offset=' + (page * 200), { headers });
        const data = await resp.json();
        const inspections = (data.results || []).filter(function(w) {
            return (w.title && w.title.match(/insp/i)) || (w.category && w.category.match(/inspect/i));
        });
        allWOs = allWOs.concat(inspections);
        hasMore = data.results && data.results.length === 200;
        page++;
        if (page > 25) break;
    }
    return allWOs;
}

// ── Get existing schedule records from Dataverse ─────
async function getExistingSchedules(dvUrl, dvToken) {
    const headers = {
        'Authorization': 'Bearer ' + dvToken,
        'OData-MaxVersion': '4.0',
        'OData-Version': '4.0',
    };
    // Paginate — may have thousands
    var all = [];
    var nextLink = dvUrl + '/api/data/v9.2/dcfg_im_schedules?$select=dcfg_im_scheduleid,dcfg_upkeep_wo_id,dcfg_visit_status,dcfg_scheduled_date&$filter=dcfg_active_flag eq true&$top=5000';

    while (nextLink) {
        const resp = await fetch(nextLink, { headers });
        const data = await resp.json();
        all = all.concat(data.value || []);
        nextLink = data['@odata.nextLink'] || null;
    }
    return all;
}

// ── Map UpKeep status to Dataverse picklist ──────────
function mapStatus(upkeepStatus) {
    if (upkeepStatus === 'complete') return 100000001;
    if (upkeepStatus === 'onHold' || upkeepStatus === 'overdue') return 100000002;
    return 100000000; // Scheduled
}

// ── Upsert WOs into Dataverse ────────────────────────
async function upsertWOs(wos, sourceName, byWoId, dvHeaders, dvToken, apiBase, log, stats) {
    for (var w = 0; w < wos.length; w++) {
        var wo = wos[w];
        var ex = byWoId[wo.id];
        var newStatus = mapStatus(wo.status);
        var newDate = wo.dueDate || null;

        if (ex) {
            var dateChanged = newDate && ex.dcfg_scheduled_date && !ex.dcfg_scheduled_date.startsWith(newDate.split('T')[0]);
            var statusChanged = ex.dcfg_visit_status !== newStatus;

            if (!dateChanged && !statusChanged) {
                stats.unchanged++;
                continue;
            }

            var patchBody = { dcfg_visit_status: newStatus };
            if (newDate) patchBody.dcfg_scheduled_date = newDate;
            if (wo.status === 'complete' && !ex.dcfg_completed_date) {
                patchBody.dcfg_completed_date = new Date().toISOString();
            }

            try {
                await fetch(apiBase + '/dcfg_im_schedules(' + ex.dcfg_im_scheduleid + ')', {
                    method: 'PATCH',
                    headers: dvHeaders,
                    body: JSON.stringify(patchBody),
                });
                stats.updated++;
            } catch (e) {
                log('[inspection-sync] Update failed ' + wo.id + ': ' + e.message);
                stats.errors++;
            }
        } else {
            var createBody = {
                dcfg_name: (wo.title || 'Inspection ' + wo.id).substring(0, 200),
                dcfg_upkeep_wo_id: wo.id,
                dcfg_upkeep_source: sourceName,
                dcfg_visit_status: newStatus,
                dcfg_active_flag: true,
                dcfg_is_first_inspection: false,
            };
            if (newDate) createBody.dcfg_scheduled_date = newDate;
            if (wo.status === 'complete') createBody.dcfg_completed_date = new Date().toISOString();

            if (wo.location) {
                try {
                    var propResp = await fetch(apiBase + "/dcfg_properties?$select=dcfg_propertyid&$filter=dcfg_upkeep_location_id eq '" + wo.location + "'&$top=1", {
                        headers: { 'Authorization': 'Bearer ' + dvToken, 'OData-MaxVersion': '4.0', 'OData-Version': '4.0' },
                    });
                    var propData = await propResp.json();
                    if (propData.value && propData.value.length > 0) {
                        createBody['dcfg_property_id@odata.bind'] = '/dcfg_properties(' + propData.value[0].dcfg_propertyid + ')';
                    }
                } catch (e) {
                    // Property lookup failed — create without link
                }
            }

            try {
                await fetch(apiBase + '/dcfg_im_schedules', {
                    method: 'POST',
                    headers: dvHeaders,
                    body: JSON.stringify(createBody),
                });
                stats.created++;
            } catch (e) {
                log('[inspection-sync] Create failed ' + wo.id + ': ' + e.message);
                stats.errors++;
            }
        }
    }
}

// ── Main sync logic ──────────────────────────────────
async function syncInspections(context) {
    var log = context.log || console.log;
    var stats = { checked: 0, created: 0, updated: 0, unchanged: 0, errors: 0 };

    // Dataverse auth
    var dvUrl = process.env.DATAVERSE_URL || 'https://org06f5de0b.api.crm.dynamics.com';
    var dvTenant = process.env.DATAVERSE_TENANT_ID;
    var dvClientId = process.env.DATAVERSE_CLIENT_ID;
    var dvClientSecret = process.env.DATAVERSE_CLIENT_SECRET;

    if (!dvTenant || !dvClientId || !dvClientSecret) {
        log('[inspection-sync] Missing DATAVERSE_TENANT_ID/CLIENT_ID/CLIENT_SECRET env vars');
        return stats;
    }

    // Build account list — primary (multi-site) + optional secondary (Bancroft)
    var accounts = [];
    if (process.env.UPKEEP_EMAIL && process.env.UPKEEP_PASSWORD) {
        accounts.push({ name: 'multisite', email: process.env.UPKEEP_EMAIL, password: process.env.UPKEEP_PASSWORD });
    }
    if (process.env.UPKEEP_EMAIL_2 && process.env.UPKEEP_PASSWORD_2) {
        accounts.push({ name: 'bancroft', email: process.env.UPKEEP_EMAIL_2, password: process.env.UPKEEP_PASSWORD_2 });
    }

    if (accounts.length === 0) {
        log('[inspection-sync] No UpKeep accounts configured');
        return stats;
    }

    log('[inspection-sync] Starting sync for ' + accounts.length + ' UpKeep account(s)...');

    var dvToken = await getDataverseToken(dvTenant, dvClientId, dvClientSecret, dvUrl);
    var existing = await getExistingSchedules(dvUrl, dvToken);

    var byWoId = {};
    for (var i = 0; i < existing.length; i++) {
        var rec = existing[i];
        if (rec.dcfg_upkeep_wo_id) byWoId[rec.dcfg_upkeep_wo_id] = rec;
    }

    var dvHeaders = {
        'Authorization': 'Bearer ' + dvToken,
        'Content-Type': 'application/json',
        'OData-MaxVersion': '4.0',
        'OData-Version': '4.0',
        'MSCRM.SolutionUniqueName': 'DCFGSystemTest',
    };
    var apiBase = dvUrl + '/api/data/v9.2';

    log('[inspection-sync] Dataverse: ' + existing.length + ' existing schedule records');

    // Process each UpKeep account
    for (var a = 0; a < accounts.length; a++) {
        var acct = accounts[a];
        log('[inspection-sync] Processing ' + acct.name + ' (' + acct.email + ')...');

        try {
            var ukToken = await getUpKeepToken(acct.email, acct.password);
            var wos = await pullUpKeepInspections(ukToken);
            stats.checked += wos.length;
            log('[inspection-sync]   ' + acct.name + ': ' + wos.length + ' inspection WOs');

            await upsertWOs(wos, acct.name, byWoId, dvHeaders, dvToken, apiBase, log, stats);
        } catch (e) {
            log('[inspection-sync]   ' + acct.name + ' FAILED: ' + e.message);
            stats.errors++;
        }
    }

    log('[inspection-sync] Done. Checked: ' + stats.checked + ', Created: ' + stats.created + ', Updated: ' + stats.updated + ', Unchanged: ' + stats.unchanged + ', Errors: ' + stats.errors);
    return stats;
}

// ── Azure Function Timer Trigger ─────────────────────
app.timer('inspectionSync', {
    schedule: '0 */30 * * * *', // Every 30 minutes
    handler: async function(timer, context) {
        context.log('[inspection-sync] Timer triggered at ' + new Date().toISOString());
        try {
            var stats = await syncInspections(context);
            context.log('[inspection-sync] Complete: ' + JSON.stringify(stats));
        } catch (e) {
            context.log('[inspection-sync] FATAL: ' + e.message);
        }
    },
});

// Export for testing
module.exports = { syncInspections };
