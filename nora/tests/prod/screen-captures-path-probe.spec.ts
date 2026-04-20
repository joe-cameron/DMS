// DCFG Path Probe — Playwright follow-up (env-aware).
// Reads the latest API-probe run for the target env, navigates to that SPA root,
// captures a UI-state snapshot node into the same runs/<id>/ directory.
//
// Target env is determined by baseURL in the playwright config:
//   https://holding.powerappsportals.com → stage
//   https://dmms1.powerappsportals.com  → prod
// Does NOT click. Read-only traversal so safe against Prod.

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const PROBE_RUNS_DIR = 'C:/DCFG/tools/path-probe/runs';

function envFromBaseUrl(u: string | undefined): 'stage' | 'prod' | 'test' | 'unknown' {
    if (!u) return 'unknown';
    if (u.includes('holding.powerappsportals.com')) return 'stage';
    if (u.includes('dmms1.powerappsportals.com'))  return 'prod';
    if (u.includes('dcfg.powerappsportals.com'))   return 'test';
    return 'unknown';
}

function findLatestRun(envFilter?: string): string {
    const entries = fs.readdirSync(PROBE_RUNS_DIR)
        .filter(n => /^\d{8}T\d{6}Z$/.test(n))
        .sort()
        .reverse();
    if (entries.length === 0) throw new Error('no probe runs found — run probe.ps1 first');
    if (!envFilter || envFilter === 'unknown') return path.join(PROBE_RUNS_DIR, entries[0]);
    for (const e of entries) {
        const summaryPath = path.join(PROBE_RUNS_DIR, e, 'summary.json');
        if (!fs.existsSync(summaryPath)) continue;
        try {
            const s = JSON.parse(fs.readFileSync(summaryPath, 'utf-8'));
            if (s.env === envFilter) return path.join(PROBE_RUNS_DIR, e);
        } catch { /* skip */ }
    }
    throw new Error(`no probe run found for env=${envFilter}`);
}

function readApiFindings(runDir: string): Record<string, any[]> {
    const nodesPath = path.join(runDir, 'nodes.jsonl');
    const findings: Record<string, any[]> = {};
    const lines = fs.readFileSync(nodesPath, 'utf-8').split(/\r?\n/).filter(l => l.trim());
    for (const l of lines) {
        const n = JSON.parse(l);
        if (!n.d1_label || !n.d4_sample) continue;
        findings[n.d1_label] = n.d4_sample;
    }
    return findings;
}

function appendNode(runDir: string, node: any) {
    const nodesPath = path.join(runDir, 'nodes.jsonl');
    fs.appendFileSync(nodesPath, JSON.stringify(node) + '\n', 'utf-8');
}

test('probe-follow-1: nav to SPA root and capture UI state', async ({ page, baseURL }) => {
    const env = envFromBaseUrl(baseURL);
    const runDir = findLatestRun(env);
    const findings = readApiFindings(runDir);

    console.log(`[follow/${env}] reusing API run: ${path.basename(runDir)}`);
    console.log(`[follow/${env}] findings: customers=${findings['customers']?.length ?? 0}  vendors=${findings['vendors']?.length ?? 0}  msas=${findings['msas']?.length ?? 0}`);

    const network: any[] = [];
    page.on('request', r => network.push({ url: r.url(), method: r.method() }));

    const t0 = Date.now();
    await page.goto('/', { waitUntil: 'domcontentloaded', timeout: 30_000 });
    const title = await page.title();
    const url = page.url();
    const hasAuthedHeader = (await page.locator('nav, header').first().count()) > 0;
    const interactives = await page.locator('a[href], button, input, select').count();

    const node = {
        d1_path: '/',
        d1_label: `${env}-root`,
        d2_action: 'NAVIGATE',
        d3_status: 200,
        d3_elapsed_ms: Date.now() - t0,
        d3_network_request_count: network.length,
        d3_api_calls: network.filter(r => r.url.includes('/_api/')).length,
        d4_title: title,
        d4_landed_url: url,
        d4_has_header: hasAuthedHeader,
        d4_interactive_count: interactives,
        run_id: path.basename(runDir),
        captured_at: new Date().toISOString(),
        adapter: `dcfg-${env}-spa`,
        probe_stage: 'follow-1-nav-only',
    };
    appendNode(runDir, node);

    await page.screenshot({ path: path.join(runDir, `follow-1-${env}-screenshot.png`), fullPage: true });

    expect(url).toBeTruthy();
    expect(title).toBeTruthy();
    console.log(`[follow/${env}] ok: ${url} — ${title}`);
});
