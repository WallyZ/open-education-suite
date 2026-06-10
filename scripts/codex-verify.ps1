[CmdletBinding()]
param(
    [ValidateSet('changed', 'full')]
    [string]$Mode = 'changed',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (& git -C . rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
    throw 'Unable to resolve repository root with git.'
}

$runId = ('{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
$cacheRoot = Join-Path $repo '.codex-cache'
$logRoot = Join-Path $cacheRoot 'logs'
$tmpRoot = Join-Path (Join-Path $cacheRoot 'tmp') $runId
$logPath = Join-Path $logRoot ("codex-verify_{0}.log" -f $runId)

[void](New-Item -ItemType Directory -Force -Path $logRoot, $tmpRoot)

$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$exitCode = 1
$pushed = $false

function Write-VerifyLog {
    param([string]$Message)
    $Message | Tee-Object -FilePath $script:logPath -Append
}

function Assert-FileExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing file: $Path"
    }
    Write-VerifyLog "ok file $Path"
}

function Assert-DirectoryExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Missing directory: $Path"
    }
    Write-VerifyLog "ok dir  $Path"
}

function Invoke-PythonCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $python = Get-Command py -ErrorAction SilentlyContinue
    if ($python) {
        $fullArgs = @('-3', '-B') + $Arguments
        & $python.Source @fullArgs 2>&1 | Tee-Object -FilePath $logPath -Append
    }
    else {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) {
            throw "Python is required for $Label."
        }
        $fullArgs = @('-B') + $Arguments
        & $python.Source @fullArgs 2>&1 | Tee-Object -FilePath $logPath -Append
    }

    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Test-TodoLifecycle {
    $previousDontWriteBytecode = $env:PYTHONDONTWRITEBYTECODE
    try {
        $env:PYTHONDONTWRITEBYTECODE = '1'

        Invoke-PythonCheck -Label 'TODO format check' -Arguments @(
            '.\scripts\lifecycle\check_todo_format.py',
            '--repo-root', '.',
            '--todo-root', 'docs/todo',
            '--min-severity', 'info',
            '--fail-on', 'error'
        )

        Invoke-PythonCheck -Label 'TODO ready-queue check' -Arguments @(
            '.\scripts\lifecycle\check_todo_ready_queue.py',
            '--repo-root', '.',
            '--todo-root', 'docs/todo',
            '--min-severity', 'info',
            '--fail-on', 'error',
            '--report', '-'
        )
    }
    finally {
        $env:PYTHONDONTWRITEBYTECODE = $previousDontWriteBytecode
    }
}

function Test-MemoryBank {
    $previousDontWriteBytecode = $env:PYTHONDONTWRITEBYTECODE
    try {
        $env:PYTHONDONTWRITEBYTECODE = '1'

        Invoke-PythonCheck -Label 'Memory-bank check' -Arguments @(
            '.\scripts\lifecycle\check_memory_bank.py',
            '--repo-root', '.',
            '--memory-dir', 'memory-bank',
            '--profile', 'cloud',
            '--require-memory-bank'
        )
    }
    finally {
        $env:PYTHONDONTWRITEBYTECODE = $previousDontWriteBytecode
    }
}

function Test-LocalAppLauncherManifest {
    $manifestPath = Join-Path $tmpRoot 'local-app-launcher.json'
    & .\scripts\export_local_app_launcher_manifest.ps1 -OutputPath $manifestPath -Json 2>&1 | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Local app launcher manifest export failed with exit code $LASTEXITCODE."
    }

    Assert-FileExists $manifestPath
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $manifest = $manifestText | ConvertFrom-Json

    if ($manifest.schema_version -ne 'local-app-launcher/v1') {
        throw 'Local app launcher manifest must use local-app-launcher/v1.'
    }
    if ($manifest.launcher_id -ne 'open-education-learner-ui-bridge') {
        throw 'Local app launcher manifest has the wrong launcher_id.'
    }
    if ($manifest.app.repo_id -ne 'open-education-suite') {
        throw 'Local app launcher manifest has the wrong app.repo_id.'
    }
    if ($manifest.app.privacy_boundary.contains_private_paths -ne $false) {
        throw 'Local app launcher manifest must not contain private paths.'
    }
    if ($manifest.app.privacy_boundary.contains_credentials -ne $false) {
        throw 'Local app launcher manifest must not contain credentials.'
    }
    if (-not (@($manifest.runtime.command) -contains 'scripts/start_learner_ui_bridge.ps1')) {
        throw 'Local app launcher runtime must start scripts/start_learner_ui_bridge.ps1.'
    }
    if ([int]$manifest.ports.live.preferred_port -ne 8786) {
        throw 'Local app launcher live port must default to 8786.'
    }
    if ([int]$manifest.ports.test.preferred_port -ne 8787) {
        throw 'Local app launcher test port must default to 8787.'
    }
    if ([int]$manifest.ports.live.preferred_port -eq [int]$manifest.ports.test.preferred_port) {
        throw 'Local app launcher live and test ports must be distinct.'
    }
    if ($manifest.health.url_template -ne 'http://127.0.0.1:{port}/ui/learner/index.html') {
        throw 'Local app launcher health URL must target the learner UI page.'
    }
    if ($manifest.windows_startup.autostart_default -ne $false) {
        throw 'Open Education learner UI launcher must not autostart by default.'
    }

    foreach ($operationName in @('start', 'stop', 'restart', 'status', 'monitor')) {
        $operation = $manifest.operations.$operationName
        if ($null -eq $operation) {
            throw "Local app launcher manifest is missing operation: $operationName"
        }
        if ($operation.requires_elevation -ne $false) {
            throw "Local app launcher operation $operationName must not require elevation."
        }
    }

    if ($manifestText -match '[A-Za-z]:\\') {
        throw 'Local app launcher manifest must not contain absolute Windows paths.'
    }
    if ($manifestText -match '(?i)youtube-automation-private|open-education-[a-z0-9_-]*private|api[_-]?key|bearer\s|secret\s*[:=]|token\s*[:=]') {
        throw 'Local app launcher manifest must not contain private repo names or credential material.'
    }
}

try {
    $env:TEMP = $tmpRoot
    $env:TMP = $tmpRoot

    Push-Location $repo
    $pushed = $true

    Write-VerifyLog "codex-verify start mode=$Mode repo=$repo"

    Assert-FileExists '.\README.md'
    Assert-FileExists '.\AGENTS.md'
    Assert-FileExists '.\.codex-cache\task-pack.md'
    Assert-FileExists '.\package.json'
    Assert-FileExists '.\package-lock.json'
    Assert-FileExists '.\playwright.config.js'
    Assert-FileExists '.\content-sources.json'
    Assert-FileExists '.\qa-live\workflow.learner_ui_live.json'
    Assert-FileExists '.\qa-live\feature_spec.learner_ui_lecture.json'
    Assert-FileExists '.\qa-live\capture.learner_ui_static.json'
    Assert-FileExists '.\docs\TODO.md'
    Assert-FileExists '.\docs\TODO_AUDIT.md'
    Assert-FileExists '.\docs\TODO_PROCESS.md'
    Assert-FileExists '.\docs\todo\00_repo_bootstrap.md'
    Assert-FileExists '.\scripts\lifecycle\check_todo_format.py'
    Assert-FileExists '.\scripts\lifecycle\check_todo_ready_queue.py'
    Test-TodoLifecycle
    Assert-FileExists '.\scripts\lifecycle\check_memory_bank.py'
    Assert-DirectoryExists '.\memory-bank'
    Test-MemoryBank
    Assert-FileExists '.\docs\codex-runbook.md'
    Assert-FileExists '.\docs\content-ingestion.md'
    Assert-FileExists '.\docs\content-package-format.md'
    Assert-FileExists '.\docs\generated-lecture-video.md'
    Assert-FileExists '.\docs\teaching-suite-opportunities.md'
    Assert-FileExists '.\docs\adaptive-teacher.md'
    Assert-FileExists '.\docs\assessment-feedback.md'
    Assert-FileExists '.\docs\learning-experience.md'
    Assert-FileExists '.\docs\interoperability-quality.md'
    Assert-FileExists '.\docs\learner-state-privacy.md'
    Assert-FileExists '.\docs\ai-teacher-integration.md'
    Assert-FileExists '.\docs\content-repo-readiness.md'
    Assert-FileExists '.\docs\teaching-quality-rubric.md'
    Assert-FileExists '.\docs\todo\TODO_12_generated_lecture_video.md'
    Assert-FileExists '.\schemas\adaptive-teacher.schema.json'
    Assert-FileExists '.\schemas\assessment.schema.json'
    Assert-FileExists '.\schemas\learner-state.schema.json'
    Assert-FileExists '.\schemas\ai-teacher.schema.json'
    Assert-FileExists '.\schemas\lecture-video.schema.json'
    Assert-FileExists '.\fixtures\learner-scenarios.json'
    Assert-FileExists '.\fixtures\assessment-items.json'
    Assert-FileExists '.\fixtures\golden-workflows.json'
    Assert-FileExists '.\fixtures\learner-state.valid.json'
    Assert-FileExists '.\fixtures\learner-state.invalid.json'
    Assert-FileExists '.\fixtures\learner-state.returning-after-gap.json'
    Assert-FileExists '.\fixtures\assessment-result.correct.json'
    Assert-FileExists '.\fixtures\ai-teacher-response.grounded.json'
    Assert-FileExists '.\fixtures\information-presentation-patterns.json'
    Assert-FileExists '.\fixtures\lecture-performance-promotion-policy.json'
    Assert-FileExists '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json'
    Assert-FileExists '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json'
    Assert-FileExists '.\fixtures\teaching-quality-benchmarks.json'
    Assert-FileExists '.\fixtures\mastery-calibration.json'
    Assert-FileExists '.\study-plans\templates\study-plan-template.md'
    Assert-FileExists '.\scripts\ingestion\scan-content-sources.ps1'
    Assert-FileExists '.\scripts\ingestion\build-content-package.ps1'
    Assert-FileExists '.\scripts\ingestion\test-content-package.ps1'
    Assert-FileExists '.\scripts\ingestion\export-courseware-metadata.ps1'
    Assert-FileExists '.\scripts\teaching\select-next-action.ps1'
    Assert-FileExists '.\scripts\teaching\start-session.ps1'
    Assert-FileExists '.\scripts\teaching\export-learner-ui-session.ps1'
    Assert-FileExists '.\scripts\teaching\lecture-paths.ps1'
    Assert-FileExists '.\scripts\teaching\learner_ui_bridge_server.py'
    Assert-FileExists '.\scripts\start_learner_ui_bridge.ps1'
    Assert-FileExists '.\scripts\manage_learner_ui_launcher.ps1'
    Assert-FileExists '.\scripts\export_local_app_launcher_manifest.ps1'
    Assert-FileExists '.\scripts\assessment\evaluate-answer.ps1'
    Assert-FileExists '.\scripts\testing\run-golden-workflows.ps1'
    Assert-FileExists '.\scripts\testing\run-golden-session.ps1'
    Assert-FileExists '.\scripts\testing\run-gdev-course-session.ps1'
    Assert-FileExists '.\scripts\testing\check-learner-ui.ps1'
    Assert-FileExists '.\scripts\testing\run-qa-live-learner-ui.ps1'
    Assert-FileExists '.\scripts\testing\run-learner-ui-playwright.ps1'
    Assert-FileExists '.\scripts\testing\run-lecture-production-smoke.ps1'
    Assert-FileExists '.\scripts\quality\check-content-quality.ps1'
    Assert-FileExists '.\scripts\quality\check-course-source-links.ps1'
    Assert-FileExists '.\scripts\quality\check-course-design-quality.ps1'
    Assert-FileExists '.\scripts\quality\check-teaching-quality.ps1'
    Assert-FileExists '.\scripts\quality\check-information-presentation-patterns.ps1'
    Assert-FileExists '.\scripts\quality\check-lecture-video.ps1'
    Assert-FileExists '.\scripts\quality\check-lecture-performance-promotion.ps1'
    Assert-FileExists '.\scripts\state\read-learner-state.ps1'
    Assert-FileExists '.\scripts\state\update-learner-state.ps1'
    Assert-FileExists '.\scripts\state\write-audit-report.ps1'
    Assert-FileExists '.\scripts\ai\build-teaching-prompt.ps1'
    Assert-FileExists '.\scripts\ai\invoke-openai-teacher.ps1'
    Assert-FileExists '.\scripts\ai\evaluate-model-output.ps1'
    Assert-FileExists '.\scripts\testing\run-live-gdev-teacher-smoke.ps1'
    Assert-FileExists '.\scripts\status\next-work.ps1'
    Assert-FileExists '.\ui\learner\index.html'
    Assert-FileExists '.\ui\learner\session-data.js'
    Assert-FileExists '.\ui\learner\styles.css'
    Assert-FileExists '.\ui\learner\app.js'
    Assert-FileExists '.\tests\learner-ui.spec.js'
    Assert-FileExists '.\tests\lecture-production-smoke.spec.js'
    Test-LocalAppLauncherManifest

    $registry = Get-Content -LiteralPath '.\content-sources.json' -Raw | ConvertFrom-Json
    if ($registry.schemaVersion -ne 1) {
        throw 'content-sources.json schemaVersion must be 1.'
    }
    if (-not $registry.contentSources -or $registry.contentSources.Count -lt 1) {
        throw 'content-sources.json must declare at least one content source.'
    }

    foreach ($source in $registry.contentSources) {
        if ([string]::IsNullOrWhiteSpace($source.id)) {
            throw 'Content source is missing id.'
        }
        if ([string]::IsNullOrWhiteSpace($source.localPath)) {
            throw "Content source $($source.id) is missing localPath."
        }
        if ([string]::IsNullOrWhiteSpace($source.contentManifest)) {
            throw "Content source $($source.id) is missing contentManifest."
        }

        $sourceRoot = Resolve-Path -LiteralPath $source.localPath
        Assert-DirectoryExists $sourceRoot.Path

        $manifestPath = Join-Path $sourceRoot.Path $source.contentManifest
        Assert-FileExists $manifestPath

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.schemaVersion -ne 1) {
            throw "Content manifest for $($source.id) must use schemaVersion 1."
        }
        if ($manifest.id -ne $source.id) {
            throw "Content manifest id '$($manifest.id)' does not match registry id '$($source.id)'."
        }

        Assert-DirectoryExists (Join-Path $sourceRoot.Path $manifest.paths.studyPlans)
        Assert-DirectoryExists (Join-Path $sourceRoot.Path $manifest.paths.resources)
    }

    $domainStudyPlans = Get-ChildItem -LiteralPath '.\study-plans' -Recurse -File |
        Where-Object { $_.FullName -notlike '*\study-plans\templates\*' -and $_.Name -ne 'README.md' }
    if ($domainStudyPlans) {
        throw ('Domain study plans remain in core repo: ' + (($domainStudyPlans | Select-Object -ExpandProperty FullName) -join ', '))
    }

    $domainResources = Get-ChildItem -LiteralPath '.\resources' -Recurse -File |
        Where-Object { $_.Name -ne 'README.md' }
    if ($domainResources) {
        throw ('Domain resources remain in core repo: ' + (($domainResources | Select-Object -ExpandProperty FullName) -join ', '))
    }

    $ingestionReportPath = Join-Path $tmpRoot 'content-ingestion-report.json'
    & .\scripts\ingestion\scan-content-sources.ps1 -OutputPath $ingestionReportPath 2>&1 | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Content source scan failed with exit code $LASTEXITCODE."
    }
    Assert-FileExists $ingestionReportPath

    $decisionOutput = & .\scripts\teaching\select-next-action.ps1 2>&1
    $decisionOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Adaptive teacher decision check failed with exit code $LASTEXITCODE."
    }
    $decisions = $decisionOutput | ConvertFrom-Json
    if ($decisions.decisionCount -lt 5) {
        throw 'Adaptive teacher fixtures must produce at least five decisions.'
    }

    $assessmentOutput = & .\scripts\assessment\evaluate-answer.ps1 -ItemId 'debugging-mcq-001' -Answer 'step into' -HintsUsed 1 2>&1
    $assessmentOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Assessment evaluation check failed with exit code $LASTEXITCODE."
    }
    $assessmentResult = $assessmentOutput | ConvertFrom-Json
    if ($assessmentResult.status -ne 'correct') {
        throw 'Assessment evaluation fixture must produce a correct result.'
    }
    if ($assessmentResult.masteryEvidence.confidenceDelta -le 0) {
        throw 'Assessment evaluation fixture must produce positive mastery evidence.'
    }

    $assessmentFixture = Get-Content -LiteralPath '.\fixtures\assessment-items.json' -Raw | ConvertFrom-Json
    if ($assessmentFixture.assessmentPolicy.defaultHighRigorType -ne 'essay') {
        throw 'Assessment policy must prefer essays as the default high-rigor assessment type.'
    }
    if ($assessmentFixture.assessmentPolicy.quizRole -notmatch 'not sufficient evidence for synthesis-level mastery') {
        throw 'Assessment policy must limit quizzes to diagnostic, retrieval, and misconception-check roles.'
    }
    $essayFixture = @($assessmentFixture.items | Where-Object { $_.type -eq 'essay' -and $_.rigor.preferredForSummative -eq $true })
    if ($essayFixture.Count -lt 1) {
        throw 'Assessment fixtures must include at least one summative synthesis essay item.'
    }
    if ([double]$essayFixture[0].masteryEvidence.confidenceDelta -le [double]$assessmentResult.masteryEvidence.confidenceDelta) {
        throw 'Synthesis essay evidence must carry stronger mastery weight than a quiz item.'
    }

    $essayAnswer = @(
        'The core mechanic is limited inventory, and it creates a dynamic where the player constantly chooses what to keep, discard, or risk losing.'
        'The aesthetic is tension because every choice feels meaningful during the play experience.'
        'As evidence, a boss fight with scarce healing items shows that the rule changes behavior because players plan movement and resource use before acting.'
        'I can compare this with an alternative unlimited inventory, which creates a different dynamic because there is less pressure.'
        'The tradeoff is cost and benefit: scarcity can sharpen decisions, but too much scarcity can frustrate learning.'
        'The lesson I would transfer into a prototype is to tune inventory limits around the emotion I want, then test whether players describe the intended pressure.'
    ) -join ' '
    $essayOutput = & .\scripts\assessment\evaluate-answer.ps1 -ItemId 'gdev-synthesis-essay-001' -Answer $essayAnswer -HintsUsed 0 2>&1
    $essayOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Synthesis essay evaluation check failed with exit code $LASTEXITCODE."
    }
    $essayResult = $essayOutput | ConvertFrom-Json
    if ($essayResult.status -ne 'correct') {
        throw 'Synthesis essay fixture must produce a correct result for a complete synthesis answer.'
    }
    if ($essayResult.masteryEvidence.evidenceType -ne 'synthesis-essay') {
        throw 'Synthesis essay fixture must produce synthesis-essay mastery evidence.'
    }
    if ([int]$essayResult.masteryEvidence.rubricEvidence.passedCriteria -ne [int]$essayResult.masteryEvidence.rubricEvidence.totalCriteria) {
        throw 'Synthesis essay fixture must pass every rubric criterion for the complete answer.'
    }

    $validStateOutput = & .\scripts\state\read-learner-state.ps1 -Path '.\fixtures\learner-state.valid.json' 2>&1
    $validStateOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Learner state validation failed with exit code $LASTEXITCODE."
    }

    $invalidFailed = $false
    try {
        & .\scripts\state\read-learner-state.ps1 -Path '.\fixtures\learner-state.invalid.json' 2>&1 | Tee-Object -FilePath $logPath -Append
        if ($LASTEXITCODE -ne 0) {
            $invalidFailed = $true
        }
    }
    catch {
        Write-VerifyLog ("expected invalid learner state failure: " + $_.Exception.Message)
        $invalidFailed = $true
    }
    if (-not $invalidFailed) {
        throw 'Invalid learner state fixture should fail validation.'
    }

    $updatedStatePath = Join-Path $tmpRoot 'learner-state.updated.json'
    & .\scripts\state\update-learner-state.ps1 -StatePath '.\fixtures\learner-state.valid.json' -AssessmentResultPath '.\fixtures\assessment-result.correct.json' -OutputPath $updatedStatePath 2>&1 | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Learner state update failed with exit code $LASTEXITCODE."
    }
    Assert-FileExists $updatedStatePath
    $auditOutput = & .\scripts\state\write-audit-report.ps1 -StatePath $updatedStatePath 2>&1
    $auditOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Learner state audit report failed with exit code $LASTEXITCODE."
    }

    $goldenOutput = & .\scripts\testing\run-golden-workflows.ps1 2>&1
    $goldenOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Golden workflow check failed with exit code $LASTEXITCODE."
    }
    $goldenResult = $goldenOutput | ConvertFrom-Json
    if ($goldenResult.errorCount -ne 0) {
        throw 'Golden workflow check reported errors.'
    }

    $goldenStatePath = Join-Path $tmpRoot 'golden-session-state.json'
    $goldenSessionOutput = & .\scripts\testing\run-golden-session.ps1 -OutputStatePath $goldenStatePath 2>&1
    $goldenSessionOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Golden teaching session check failed with exit code $LASTEXITCODE."
    }
    $goldenSessionResult = $goldenSessionOutput | ConvertFrom-Json
    if ($goldenSessionResult.errorCount -ne 0) {
        throw 'Golden teaching session check reported errors.'
    }

    $gdevSessionOutput = & .\scripts\testing\run-gdev-course-session.ps1 -WorkingRoot $tmpRoot 2>&1
    $gdevSessionOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Game-development course session check failed with exit code $LASTEXITCODE."
    }
    $gdevSessionResult = $gdevSessionOutput | ConvertFrom-Json
    if ($gdevSessionResult.errorCount -ne 0) {
        throw 'Game-development course session check reported errors.'
    }

    $learnerUiOutput = & .\scripts\testing\check-learner-ui.ps1 2>&1
    $learnerUiOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Learner UI check failed with exit code $LASTEXITCODE."
    }
    $learnerUiResult = $learnerUiOutput | ConvertFrom-Json
    if ($learnerUiResult.errorCount -ne 0) {
        throw 'Learner UI check reported errors.'
    }

    $expectedLearnerSessionDataPath = Join-Path $tmpRoot 'learner-ui-session-data.js'
    $learnerSessionExportOutput = & .\scripts\teaching\export-learner-ui-session.ps1 -OutputPath $expectedLearnerSessionDataPath 2>&1
    $learnerSessionExportOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Learner UI session data export failed with exit code $LASTEXITCODE."
    }
    $currentLearnerSessionData = Get-Content -LiteralPath '.\ui\learner\session-data.js' -Raw
    $expectedLearnerSessionData = Get-Content -LiteralPath $expectedLearnerSessionDataPath -Raw
    if ($currentLearnerSessionData -ne $expectedLearnerSessionData) {
        throw 'Learner UI session data is stale. Run .\scripts\teaching\export-learner-ui-session.ps1.'
    }

    $aiPromptOutput = & .\scripts\ai\build-teaching-prompt.ps1 2>&1
    $aiPromptOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "AI teacher prompt build failed with exit code $LASTEXITCODE."
    }
    $aiPrompt = $aiPromptOutput | ConvertFrom-Json
    if (@($aiPrompt.sourceSnippets).Count -lt 1) {
        throw 'AI teacher prompt must include source snippets.'
    }

    $aiEvalOutput = & .\scripts\ai\evaluate-model-output.ps1 2>&1
    $aiEvalOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "AI teacher output evaluation failed with exit code $LASTEXITCODE."
    }
    $aiEval = $aiEvalOutput | ConvertFrom-Json
    if ($aiEval.errorCount -ne 0) {
        throw 'AI teacher output evaluation reported errors.'
    }

    $packageRoot = Join-Path $tmpRoot 'content-package'
    $packageOutput = & .\scripts\ingestion\build-content-package.ps1 -OutputRoot $packageRoot 2>&1
    $packageOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Content package build failed with exit code $LASTEXITCODE."
    }
    $packageCheckOutput = & .\scripts\ingestion\test-content-package.ps1 -PackageRoot $packageRoot 2>&1
    $packageCheckOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Content package validation failed with exit code $LASTEXITCODE."
    }
    $packageCheck = $packageCheckOutput | ConvertFrom-Json
    if ($packageCheck.errorCount -ne 0) {
        throw 'Content package validation reported errors.'
    }
    $coursewareMetadataPath = Join-Path $tmpRoot 'courseware-metadata.json'
    $coursewareMetadataOutput = & .\scripts\ingestion\export-courseware-metadata.ps1 -PackageRoot $packageRoot -OutputPath $coursewareMetadataPath 2>&1
    $coursewareMetadataOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Courseware metadata export failed with exit code $LASTEXITCODE."
    }
    Assert-FileExists $coursewareMetadataPath
    $coursewareMetadata = Get-Content -LiteralPath $coursewareMetadataPath -Raw | ConvertFrom-Json
    if ($coursewareMetadata.schema_version -ne 'content-courseware/course/v1') {
        throw 'Courseware metadata export must use content-courseware/course/v1.'
    }
    if ($coursewareMetadata.privacy_boundary.contains_learner_pii -ne $false) {
        throw 'Courseware metadata export must not contain learner PII.'
    }
    if ($coursewareMetadata.privacy_boundary.contains_private_course_content -ne $false) {
        throw 'Courseware metadata export must not contain private course content.'
    }
    if (@($coursewareMetadata.learning_outcomes).Count -lt 1 -or @($coursewareMetadata.modules).Count -lt 1) {
        throw 'Courseware metadata export must include outcomes and modules.'
    }

    $qualityOutput = & .\scripts\quality\check-content-quality.ps1 2>&1
    $qualityOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Content quality check failed with exit code $LASTEXITCODE."
    }
    $qualityResult = $qualityOutput | ConvertFrom-Json
    if ($qualityResult.errorCount -ne 0) {
        throw 'Content quality check reported errors.'
    }

    $courseSourceLinkOutput = & .\scripts\quality\check-course-source-links.ps1 2>&1
    $courseSourceLinkOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Course source-link audit failed with exit code $LASTEXITCODE."
    }
    $courseSourceLinkResult = $courseSourceLinkOutput | ConvertFrom-Json
    if ($courseSourceLinkResult.errorCount -ne 0) {
        throw 'Course source-link audit reported errors.'
    }
    if ($courseSourceLinkResult.readOnly -ne $true -or $courseSourceLinkResult.networkAccess -ne 'none') {
        throw 'Course source-link audit must be read-only and offline-safe by default.'
    }

    $courseDesignQualityOutput = & .\scripts\quality\check-course-design-quality.ps1 2>&1
    $courseDesignQualityOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Course design quality gate failed with exit code $LASTEXITCODE."
    }
    $courseDesignQualityResult = $courseDesignQualityOutput | ConvertFrom-Json
    if ($courseDesignQualityResult.errorCount -ne 0) {
        throw 'Course design quality gate reported errors.'
    }
    if ($courseDesignQualityResult.readOnly -ne $true -or $courseDesignQualityResult.networkAccess -ne 'none') {
        throw 'Course design quality gate must be read-only and offline-safe by default.'
    }

    $teachingQualityOutput = & .\scripts\quality\check-teaching-quality.ps1 2>&1
    $teachingQualityOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Teaching quality check failed with exit code $LASTEXITCODE."
    }
    $teachingQualityResult = $teachingQualityOutput | ConvertFrom-Json
    if ($teachingQualityResult.errorCount -ne 0) {
        throw 'Teaching quality check reported errors.'
    }

    $informationPresentationOutput = & .\scripts\quality\check-information-presentation-patterns.ps1 2>&1
    $informationPresentationOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Information presentation pattern check failed with exit code $LASTEXITCODE."
    }
    $informationPresentationResult = $informationPresentationOutput | ConvertFrom-Json
    if ($informationPresentationResult.errorCount -ne 0) {
        throw 'Information presentation pattern check reported errors.'
    }
    if ($informationPresentationResult.readOnly -ne $true -or $informationPresentationResult.networkAccess -ne 'none') {
        throw 'Information presentation pattern check must be read-only and offline-safe by default.'
    }

    $lectureVideoOutput = & .\scripts\quality\check-lecture-video.ps1 2>&1
    $lectureVideoOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Lecture video check failed with exit code $LASTEXITCODE."
    }
    $lectureVideoResult = $lectureVideoOutput | ConvertFrom-Json
    if ($lectureVideoResult.errorCount -ne 0) {
        throw 'Lecture video check reported errors.'
    }

    $lecturePerformancePromotionOutput = & .\scripts\quality\check-lecture-performance-promotion.ps1 2>&1
    $lecturePerformancePromotionOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Lecture performance promotion gate failed with exit code $LASTEXITCODE."
    }
    $lecturePerformancePromotionResult = $lecturePerformancePromotionOutput | ConvertFrom-Json
    if ($lecturePerformancePromotionResult.errorCount -ne 0) {
        throw 'Lecture performance promotion gate reported errors.'
    }
    if ($lecturePerformancePromotionResult.readOnly -ne $true -or $lecturePerformancePromotionResult.networkAccess -ne 'none') {
        throw 'Lecture performance promotion gate must be read-only and offline-safe by default.'
    }

    $lectureProductionSmokeOutput = & .\scripts\testing\run-lecture-production-smoke.ps1 2>&1
    $lectureProductionSmokeOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Lecture production smoke failed with exit code $LASTEXITCODE."
    }

    $qaLiveOutput = & .\scripts\testing\run-qa-live-learner-ui.ps1 2>&1
    $qaLiveOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "qa-live learner UI workflow failed with exit code $LASTEXITCODE."
    }

    $nextWorkOutput = & .\scripts\status\next-work.ps1 2>&1
    $nextWorkOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Next work helper failed with exit code $LASTEXITCODE."
    }
    $nextWork = $nextWorkOutput | ConvertFrom-Json
    if ($nextWork.status -ne 'open' -and $nextWork.status -ne 'none') {
        throw 'Next work helper returned an invalid status.'
    }
    if ([int]$nextWork.todoFileCount -lt 1) {
        throw 'Next work helper must report the number of TODO files scanned.'
    }
    if ([int]$nextWork.checkedItemCount -lt ([int]$nextWork.openItemCount + [int]$nextWork.completedItemCount)) {
        throw 'Next work helper reported inconsistent TODO item counts.'
    }
    if ($nextWork.status -eq 'none' -and [int]$nextWork.openItemCount -ne 0) {
        throw 'Next work helper reported no open item while openItemCount is non-zero.'
    }

    Write-VerifyLog "codex-verify passed mode=$Mode log=$logPath"
    $exitCode = 0
}
catch {
    Write-VerifyLog ("codex-verify error: " + $_.Exception.Message)
    $exitCode = 1
}
finally {
    if ($pushed) {
        Pop-Location
    }
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp

    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

if ($exitCode -ne 0) {
    Write-Output ("codex-verify failed: mode={0} exit={1} log={2}" -f $Mode, $exitCode, $logPath)
    exit $exitCode
}

Write-Output ("codex-verify passed: mode={0} log={1}" -f $Mode, $logPath)
exit 0
