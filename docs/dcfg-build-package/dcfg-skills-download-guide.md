# DCFG Skills Download Guide

Categorized by business function. Each entry includes the direct install command or repo link, what it does, and why it's relevant to DCFG.

---

## CATEGORY 1: Software Development Methodology

These skills govern how Claude Code approaches building and modifying the DCFG Contracting Suite, Power Pages SPA, Power Automate flows, and any future applications.

### obra/superpowers (Plugin Marketplace)
**What it provides:** Complete development workflow — brainstorming, spec writing, implementation planning, TDD (red-green-refactor), systematic debugging (4-phase: reproduce → isolate → hypothesize → fix), subagent-driven development with code review, git worktree management.

**Install:**
```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```
**Repo:** https://github.com/obra/superpowers

**Individual skills inside:**
- `/brainstorming` — Socratic requirements refinement before coding
- `/test-driven-development` — Enforces failing test before implementation
- `/systematic-debugging` — 4-phase root cause analysis with forced architectural review after 3 failed fixes
- `/subagent-driven-development` — Dispatches fresh subagents per task with two-stage review
- `/using-git-worktrees` — Isolated branches per feature
- `/writing-plans` — Breaks designs into 2-5 minute tasks with exact file paths
- `/finishing-a-development-branch` — Guides completion and merge
- `/requesting-code-review` — Structured review process

**DCFG relevance:** This is how Claude Code should approach every change to the SPA, every new React component, every PowerShell script. The debugging skill alone would have saved hours on the `dcfg_template_field` seed script 400 errors.

---

## CATEGORY 2: Testing & Quality Assurance

### Playwright Browser Automation
**What it provides:** Claude controls a real browser — clicks buttons, fills forms, takes screenshots, verifies UI behavior. Tests authentication flows, JavaScript-rendered content, and complex user interactions.

**Install:**
```
/plugin add https://github.com/anthropics/skills
```
(Part of Anthropic's official skills — `webapp-testing`)

**Repo:** https://github.com/anthropics/skills/tree/main/skills/webapp-testing

**DCFG relevance:** This is how you test the Power Pages SPA screens end-to-end. The Playwright test framework you're building for the Contracting Suite can be driven by this skill — it catches UI bugs that static analysis misses.

### pypict-claude-skill
**What it provides:** Pairwise combinatorial test case design using PICT. Generates optimized test suites that cover parameter combinations without exhaustive testing.

**Repo:** https://github.com/anthropics/skills (community section) — search for `pypict`

**DCFG relevance:** Contract wizard has multiple paths (customer type × pricing mode × location count × amendment state). Combinatorial testing covers the matrix without writing hundreds of individual tests.

---

## CATEGORY 3: Security & Code Auditing

### Trail of Bits Security Skills
**What it provides:** Professional-grade static analysis workflows — CodeQL, Semgrep, variant analysis (finding related vulnerabilities across a codebase), structured code auditing methodology.

**Repo:** https://github.com/trailofbits/skills

**DCFG relevance:** The SPA handles authentication, CSRF tokens, role-based access, and financial data. These skills audit the React components and portalApi.js for vulnerabilities that manual review misses. Written by a firm that does real security audits for paying clients.

### VibeSec
**What it provides:** Helps Claude write secure code proactively — prevents common vulnerabilities during development rather than catching them after.

**Repo:** https://github.com/anthropics/skills (community) — search for `vibesec`

**DCFG relevance:** Every PATCH to Dataverse, every CSRF token flow, every role-restricted UI element. Security by default, not security by audit.

---

## CATEGORY 4: Frontend Design & UI

### Anthropic frontend-design (Official)
**What it provides:** Forces Claude to commit to a bold design direction before writing code. Prevents generic "AI slop" aesthetics. Outputs distinctive typography, purposeful color palettes, and intentional animations.

**Install:**
```
/plugin marketplace add anthropics/skills
/plugin install example-skills@anthropic-agent-skills
```

**DCFG relevance:** When building new screens or the Decades Brain chat interface, this skill pushes past the default Bootstrap look. Combined with your dcfg-ux-psychology skill (which handles the DCFG-specific design tokens and rules), this covers both the creative direction and the system constraints.

---

## CATEGORY 5: Document Generation

### Anthropic docx / pptx / pdf / xlsx (Official)
**What it provides:** Production-grade document creation skills. These are the same skills powering Claude.ai's document capabilities. You already have them loaded.

**Repo:** https://github.com/anthropics/skills/tree/main/skills/docx (and /pptx, /pdf, /xlsx)

**DCFG relevance:** RPT-WO-001, RPT-PGM-001, RPT-CAP-001 all generate PowerPoint. The Capital Replacement Plan also has an HTML variant. These skills are the execution layer for Decades Brain document generation.

### revealjs-skill
**What it provides:** Generate polished presentations using the Reveal.js HTML framework. Alternative to PowerPoint for web-delivered presentations.

**Repo:** https://github.com/BehiSecc/awesome-claude-skills (listed) — search for `revealjs`

**DCFG relevance:** The interactive HTML version of the Capital Replacement Plan (RPT-CAP-001-HTML) could be built using Reveal.js instead of a custom HTML page. Worth evaluating as an alternative presentation format for customer-facing reports.

---

## CATEGORY 6: Research & Analysis

### sanjay3290/ai-skills — deep-research
**What it provides:** Autonomous multi-step research using Gemini Deep Research Agent. Market analysis, competitive landscaping, literature reviews. Already installed.

**Install:**
```
/plugin add https://github.com/sanjay3290/ai-skills
/plugin install deep-research@ai-skills
```
**Repo:** https://github.com/sanjay3290/ai-skills/tree/main/skills/deep-research

**DCFG relevance:** Market rate research for bid comparisons, vendor background checks, equipment lifespan research to validate ASHRAE/BOMA benchmarks.

### 199-biotechnologies/claude-deep-research-skill
**What it provides:** Enterprise-grade 8-phase research pipeline — scope, plan, retrieve (parallel), triangulate, outline, synthesize, critique, refine, package. Source credibility scoring. Auto-continuation for unlimited length. No external API dependency (pure Claude).

**Repo:** https://github.com/199-biotechnologies/claude-deep-research-skill

**DCFG relevance:** Heavier alternative to the sanjay3290 skill. Use for comprehensive vendor due diligence, equipment benchmark validation, or when you need a sourced research document rather than a quick answer.

---

## CATEGORY 7: Data & Database Operations

### sanjay3290/ai-skills — postgres
**What it provides:** Safe read-only SQL queries against PostgreSQL databases with multi-connection support and defense-in-depth security.

**Install:**
```
/plugin install postgres@ai-skills
```
**Repo:** https://github.com/sanjay3290/ai-skills/tree/main/skills/postgres

**DCFG relevance:** If any DCFG data lands in PostgreSQL (reporting warehouse, analytics), this provides safe query access. The defense-in-depth pattern (read-only enforcement) is a model for how Decades Brain should access any database.

### Excel MCP Server
**What it provides:** Claude gains native control over Excel files — read, write, analyze, execute formulas, produce charts. No Microsoft Excel installation required.

**Repo:** Search MCP marketplace for `excel-mcp-server`

**DCFG relevance:** Bid comparison spreadsheets, cost analysis workbooks, budget tracking sheets. Field staff and contractors often submit data in Excel. This lets Claude process it directly.

---

## CATEGORY 8: RFP, Bid & Procurement

**No credible open-source Claude skills exist for construction-specific RFP/bid workflows.** The tools in this space are all SaaS products (ContraVault, DeepRFP, Awarded AI, etc.) — not downloadable skills.

**What this means for DCFG:** This is a skill you need to build, not download. The bid comparison presentation workflow — receiving contractor bids, normalizing them into a comparison matrix, scoring against criteria, generating a presentation for the customer — is DCFG-specific enough that a generic skill wouldn't help anyway.

**Recommended approach:** Build a custom DCFG skill (`dcfg-bid-comparison`) that:
- Reads bid responses (uploaded PDFs or structured data in Dataverse)
- Normalizes pricing into a comparison matrix (T&M rates, unit costs, markup percentages)
- Scores against weighted criteria (price, qualifications, schedule, references, insurance/bonding)
- Generates a bid comparison presentation using the pptx skill with DCFG design tokens
- Produces a recommendation summary with the scoring rationale

This would be a Phase 2 skill after the Contracting Suite beta stabilizes. The autoresearch loop can optimize it once it exists.

---

## CATEGORY 9: Field Operations & Facilities Management

**No credible Claude skills exist for construction field operations.** The industry tools are proprietary platforms (Procore, PlanGrid, UpKeep, BuildOps) — not skill-based.

**What this means for DCFG:** Your existing skills (power-pages-content-ops, dataverse-schema-ops) plus the company brain and Decades Brain are already more advanced than anything publicly available for this domain. The property location intelligence overlay and asset lifespan tracking you designed today are novel — nobody has published a skill for this.

**Adjacent skills worth monitoring:**
- UpKeep API integration — when OI-06 goes live, a skill that wraps the UpKeep REST API for work order queries, asset lookups, and cert verification
- Procore MCP — if DCFG ever connects to Procore, an MCP server for project data would integrate with Decades Brain

---

## CATEGORY 10: Google Workspace / Microsoft 365

### sanjay3290/ai-skills — Google Workspace suite
**What it provides:** Gmail, Google Calendar, Google Chat, Google Docs, Google Sheets, Google Slides, Google Drive — each as a separate skill.

**Install:**
```
/plugin install gmail@ai-skills
/plugin install google-calendar@ai-skills
/plugin install google-drive@ai-skills
/plugin install google-sheets@ai-skills
```
**Repo:** https://github.com/sanjay3290/ai-skills

**DCFG relevance:** Limited — DCFG is a Microsoft shop. But if any customers or vendors operate on Google Workspace, these skills let Claude interact with their documents when shared.

### Google Workspace CLI (gws)
**What it provides:** Unified CLI that discovers all Google Workspace APIs via Discovery Service. Built-in MCP server. One command = full Workspace access.

**Install:**
```
npm install -g @googleworkspace/cli
gws mcp -s drive,gmail,calendar,sheets
```
**Repo:** https://github.com/googleworkspace/cli

**DCFG relevance:** Same as above — secondary priority given Microsoft ecosystem. But 4,900 stars in 3 days suggests this will be important industry-wide.

---

## CATEGORY 11: Autonomous Agent Patterns

### Karpathy autoresearch pattern (already installed)
**What it provides:** Generate → evaluate → mutate → repeat loop for self-improving any process. Already adapted for DCFG skill improvement.

**Installed as:** autoresearch-diagrams skill (local)

**DCFG relevance:** The autoresearch improvement plan for all 4 DCFG skills uses this pattern. Also applicable to bid comparison optimization, report template refinement, and any process where you can define binary eval criteria.

### planning-with-files
**What it provides:** Manus-style persistent markdown planning — the agent maintains a plan file that survives across sessions. 9.7K stars.

**Repo:** https://github.com/planning-with-files (search GitHub)

**DCFG relevance:** This is the session handoff pattern from the Anthropic blog post we discussed. Directly relevant to maintaining DCFG project state across Claude Code sessions. Complements the `session-state.json` pattern in the company brain.

---

## CATEGORY 12: Skill Repositories (Meta — Discovery & Browsing)

These are not skills themselves — they're where you find more skills.

| Repo | What it is | Link |
|---|---|---|
| anthropics/skills | Official Anthropic skills. Production quality. Reference implementations. | https://github.com/anthropics/skills |
| obra/superpowers | Jesse Vincent's methodology + skills. Highest credibility author in the ecosystem. | https://github.com/obra/superpowers |
| ComposioHQ/awesome-claude-skills | Automation-focused curation. Strong on integrations. | https://github.com/ComposioHQ/awesome-claude-skills |
| sickn33/antigravity-awesome-skills | Largest collection (1,200+). Good for discovery, variable quality. | https://github.com/sickn33/antigravity-awesome-skills |
| VoltAgent/awesome-agent-skills | 500+ skills with cross-compatibility notes. Well organized. | https://github.com/VoltAgent/awesome-agent-skills |
| hesreallyhim/awesome-claude-code | Broader Claude Code resources — not just skills but agents, plugins, hooks, tutorials. | https://github.com/hesreallyhim/awesome-claude-code |
| sanjay3290/ai-skills | 19 practical skills. Database, Google Workspace, research, media. | https://github.com/sanjay3290/ai-skills |
| trailofbits/skills | Security audit skills from a real security firm. | https://github.com/trailofbits/skills |
| K-Dense-AI/claude-scientific-skills | 170+ scientific/research skills. Deep domain coverage. | https://github.com/K-Dense-AI/claude-scientific-skills |
| SkillsMP | Search engine for 400K+ skills. Filter by category, author, compatibility. | https://skillsmp.com |
| OrchestrateOS Forum | Community Q&A — skills troubleshooting, what works, what doesn't. | https://app.orchestrateos.io/forum |
| Anthropic Discord | 75K members. Real-time discussion. | https://discord.com/invite/6PPFFzqPDZ |

---

## Summary: What to Install Now vs Build Later

### Install Now (proven, credible, immediately useful)
1. **obra/superpowers** — development methodology for every coding session
2. **Trail of Bits security skills** — security audit for the SPA
3. **sanjay3290/ai-skills** — deep-research + database access (already partially installed)

### Already Loaded (keep using)
4. **Anthropic docx/pptx/pdf/xlsx** — document generation
5. **Anthropic frontend-design** — UI quality
6. **Anthropic webapp-testing** — Playwright browser automation
7. **autoresearch-diagrams** — self-improving loop (installed today)

### Build Custom (DCFG-specific, no public skill exists)
8. **dcfg-bid-comparison** — RFP response normalization, scoring, presentation generation
9. **dcfg-upkeep-integration** — UpKeep API wrapper when OI-06 goes live
10. **dcfg-field-ops** — Field staff mobile workflows, site visit protocols

### Monitor (not needed yet but worth watching)
11. **planning-with-files** — Session handoff patterns
12. **Google Workspace CLI** — If cross-ecosystem collaboration becomes needed
