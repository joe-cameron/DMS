# Replace onboarding checklist template steps for testing
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\Core.ps1"
. "C:\DCFG\PowerApps-Samples\dataverse\webapi\PS\TableOperations.ps1"

Connect 'https://org0c17e98d.crm.dynamics.com/'
$OrgUrl = 'https://org0c17e98d.crm.dynamics.com/api/data/v9.2'

$Test1 = 'Test1@decades-cg.com'
$Test2 = 'Test2@decades-cg.com'

Invoke-DataverseCommands {
    if ($baseURI -notmatch 'org0c17e98d') { Write-Host "ABORT: Wrong env!" -ForegroundColor Red; return }

    # ── Step 1: Hard-delete existing template steps (no active_flag on this table) ──
    Write-Host "=== DELETE existing template steps ===" -ForegroundColor Cyan
    $existing = (Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists?`$filter=dcfg_is_template eq true&`$select=dcfg_onboarding_checklistid,dcfg_step_name&`$top=50" -Headers $baseHeaders).value
    Write-Host "  Found $($existing.Count) template steps" -ForegroundColor Yellow

    $deleted = 0
    foreach ($s in $existing) {
        try {
            Invoke-RestMethod -Uri "$OrgUrl/dcfg_onboarding_checklists($($s.dcfg_onboarding_checklistid))" -Method DELETE -Headers $baseHeaders | Out-Null
            $deleted++
        } catch {
            Write-Host "  FAIL delete $($s.dcfg_step_name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "  Deleted: $deleted" -ForegroundColor Green

    # ── Step 2: Create new test steps ──
    Write-Host "`n=== CREATE new test steps ===" -ForegroundColor Cyan

    $steps = @(
        # Phase 0: Sales (100000000)
        @{ num=1;  phase=100000000; name='Test proposal signed';              resp='Test1'; acctN='Test1'; respE=$Test1; acctE=$Test1; cons=$Test2; consN='Test2'; inf=$Test2; infN='Test2' },
        @{ num=2;  phase=100000000; name='Client data entered in portal';     resp='Test2'; acctN='Test1'; respE=$Test2; acctE=$Test1; cons=$null;  consN=$null;  inf=$Test1; infN='Test1' },
        @{ num=3;  phase=100000000; name='Invoice sent and paid';             resp='Test1'; acctN='Test2'; respE=$Test1; acctE=$Test2; cons=$Test1; consN='Test1'; inf=$Test2; infN='Test2' },

        # Phase 1: Contracting (100000001)
        @{ num=4;  phase=100000001; name='Contract generated via DocGen';     resp='Test1'; acctN='Test1'; respE=$Test1; acctE=$Test1; cons=$Test2; consN='Test2'; inf=$Test2; infN='Test2' },
        @{ num=5;  phase=100000001; name='Contract sent to client';           resp='Test2'; acctN='Test1'; respE=$Test2; acctE=$Test1; cons=$null;  consN=$null;  inf=$Test1; infN='Test1' },
        @{ num=6;  phase=100000001; name='Signed contract returned';          resp='Test1'; acctN='Test2'; respE=$Test1; acctE=$Test2; cons=$Test1; consN='Test1'; inf=$Test2; infN='Test2' },

        # Phase 2: Setup (100000002)
        @{ num=7;  phase=100000002; name='UpKeep locations configured';       resp='Test2'; acctN='Test2'; respE=$Test2; acctE=$Test2; cons=$Test1; consN='Test1'; inf=$Test1; infN='Test1' },
        @{ num=8;  phase=100000002; name='Portal access granted';             resp='Test1'; acctN='Test1'; respE=$Test1; acctE=$Test1; cons=$Test2; consN='Test2'; inf=$Test2; infN='Test2' },
        @{ num=9;  phase=100000002; name='Client data review complete';       resp='Test2'; acctN='Test1'; respE=$Test2; acctE=$Test1; cons=$Test1; consN='Test1'; inf=$Test2; infN='Test2' },

        # Phase 3: Training (100000003)
        @{ num=10; phase=100000003; name='Kickoff meeting held';              resp='Test1'; acctN='Test1'; respE=$Test1; acctE=$Test1; cons=$Test2; consN='Test2'; inf=$Test2; infN='Test2' },
        @{ num=11; phase=100000003; name='Portal training delivered';         resp='Test2'; acctN='Test2'; respE=$Test2; acctE=$Test2; cons=$Test1; consN='Test1'; inf=$Test1; infN='Test1' },
        @{ num=12; phase=100000003; name='Emergency protocols reviewed';      resp='Test1'; acctN='Test2'; respE=$Test1; acctE=$Test2; cons=$Test2; consN='Test2'; inf=$Test1; infN='Test1' },

        # Phase 4: Go-Live (100000004)
        @{ num=13; phase=100000004; name='Inspection schedule created';       resp='Test2'; acctN='Test1'; respE=$Test2; acctE=$Test1; cons=$Test1; consN='Test1'; inf=$Test2; infN='Test2' },
        @{ num=14; phase=100000004; name='Client go-live confirmed';          resp='Test1'; acctN='Test1'; respE=$Test1; acctE=$Test1; cons=$Test2; consN='Test2'; inf=$Test2; infN='Test2' },
        @{ num=15; phase=100000004; name='Daily check-in cycle started';      resp='Test2'; acctN='Test2'; respE=$Test2; acctE=$Test2; cons=$Test1; consN='Test1'; inf=$Test1; infN='Test1' }
    )

    $created = 0
    foreach ($s in $steps) {
        $body = @{
            dcfg_step_name         = $s.name
            dcfg_step_number       = $s.num
            dcfg_phase             = $s.phase
            dcfg_is_template       = $true
            dcfg_responsible_person = $s.resp
            dcfg_assigned_email    = $s.respE
            dcfg_assigned_name     = $s.resp
            dcfg_accountable       = $s.acctN
            dcfg_accountable_email = $s.acctE
            dcfg_accountable_name  = $s.acctN
            dcfg_dependency_type   = 100000000
        }

        if ($s.cons) {
            $body['dcfg_consulted'] = "[{`"email`":`"$($s.cons)`",`"opted_in`":true,`"name`":`"$($s.consN)`"}]"
        }
        if ($s.inf) {
            $body['dcfg_informed'] = "[{`"email`":`"$($s.inf)`",`"opted_in`":true,`"name`":`"$($s.infN)`"}]"
        }

        try {
            $id = New-Record -setName 'dcfg_onboarding_checklists' -body $body
            Write-Host "  #$($s.num) $($s.name) => $id" -ForegroundColor Green
            $created++
        } catch {
            Write-Host "  FAIL #$($s.num) $($s.name): $($_.Exception.Message)" -ForegroundColor Red
            if ($_.ErrorDetails.Message) {
                $d = $_.ErrorDetails.Message
                if ($d.Length -gt 400) { $d = $d.Substring(0, 400) }
                Write-Host "    $d" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
    Write-Host "  Deleted: $deleted old steps" -ForegroundColor Yellow
    Write-Host "  Created: $created new test steps" -ForegroundColor Green
}
