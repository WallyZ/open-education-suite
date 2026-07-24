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

function Test-VoiceStudioSessionContract {
    $sessionPath = Join-Path $tmpRoot 'voice-studio-session.json'
    & .\scripts\teaching\export-voice-session-contract.ps1 -OutputPath $sessionPath 2>&1 | Tee-Object -FilePath $logPath -Append

    Assert-FileExists $sessionPath
    $sessionText = Get-Content -LiteralPath $sessionPath -Raw
    $session = $sessionText | ConvertFrom-Json

    if ($session.schema_version -ne 'voice-studio/session/v1') {
        throw 'Voice Studio session contract must use voice-studio/session/v1.'
    }
    if ($session.session_id -notmatch '^[a-z0-9][a-z0-9._-]*$') {
        throw 'Voice Studio session_id must be sanitized.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$session.speaker_ref)) {
        throw 'Voice Studio session must include speaker_ref.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$session.script_ref)) {
        throw 'Voice Studio session must include script_ref.'
    }
    if ($session.recording_plan.mode -ne 'practice') {
        throw 'Open Education Voice Studio adapter must default to practice mode.'
    }
    if ([int]$session.recording_plan.target_wpm -lt 80 -or [int]$session.recording_plan.target_wpm -gt 220) {
        throw 'Voice Studio target_wpm must stay within the shared contract range.'
    }
    if (@($session.recording_plan.segments).Count -lt 2) {
        throw 'Voice Studio session must expose multiple logical lecture/practice segments.'
    }
    foreach ($segment in @($session.recording_plan.segments)) {
        if ([string]$segment.segment_id -notmatch '^[a-z0-9][a-z0-9._-]*$') {
            throw "Voice Studio segment_id is not sanitized: $($segment.segment_id)"
        }
        if ([double]$segment.estimated_seconds -le 0) {
            throw "Voice Studio segment estimated_seconds must be positive: $($segment.segment_id)"
        }
        if ([string]$segment.text_ref -match '(?i)verb = player action|quiet space|pause here') {
            throw 'Voice Studio segment text_ref must not contain raw lecture text.'
        }
    }
    if ($session.privacy_boundary.contains_raw_audio -ne $false) {
        throw 'Voice Studio session must not contain raw audio.'
    }
    if ($session.privacy_boundary.contains_voiceprint -ne $false) {
        throw 'Voice Studio session must not contain voiceprints.'
    }
    if ($session.privacy_boundary.contains_model_artifact -ne $false) {
        throw 'Voice Studio session must not contain model artifacts.'
    }
    if ($session.privacy_boundary.private_artifacts_required -ne $false) {
        throw 'Open Education Voice Studio adapter should not require private artifacts.'
    }
    if (@($session.privacy_boundary.allowed_artifact_refs).Count -lt 1) {
        throw 'Voice Studio session must include at least one logical artifact ref.'
    }
    if ([int]$session.qa_targets.sample_rate_hz -ne 48000) {
        throw 'Voice Studio QA target sample rate should be 48000 Hz for production-quality capture.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$session.outputs.metadata_ref) -or [string]::IsNullOrWhiteSpace([string]$session.outputs.qa_report_ref)) {
        throw 'Voice Studio session must include logical output refs.'
    }
    if ($sessionText -match '[A-Za-z]:\\') {
        throw 'Voice Studio session must not contain absolute Windows paths.'
    }
    if ($sessionText -match '(?i)generated-lectures\\|media\\audio|\.wav|\.mp3|\.flac|sha256|youtube-automation-private|api[_-]?key|bearer\s|secret\s*[:=]|token\s*[:=]') {
        throw 'Voice Studio session must not leak media paths, file names, hashes, private repos, or credential material.'
    }
}

function Test-AssessmentMasteryContract {
    $contractPath = Join-Path $tmpRoot 'assessment-mastery-contract.json'
    & .\scripts\assessment\export-assessment-mastery-contract.ps1 -OutputPath $contractPath 2>&1 | Tee-Object -FilePath $logPath -Append

    Assert-FileExists $contractPath
    $contractText = Get-Content -LiteralPath $contractPath -Raw
    $contract = $contractText | ConvertFrom-Json

    if ($contract.schema_version -ne 'assessment-mastery/assessment/v1') {
        throw 'Assessment Mastery contract must use assessment-mastery/assessment/v1.'
    }
    if ($contract.assessment_id -notmatch '^[a-z0-9][a-z0-9._-]*$') {
        throw 'Assessment Mastery assessment_id must be sanitized.'
    }
    if ([string]$contract.course_ref -notmatch '^course:[a-z0-9._:-]+$') {
        throw 'Assessment Mastery contract must include a logical course_ref.'
    }
    if ($contract.assessment_type -ne 'essay') {
        throw 'Default Assessment Mastery export must use the essay synthesis fixture.'
    }
    if (@($contract.rubric.criteria).Count -lt 1) {
        throw 'Assessment Mastery contract must include rubric criteria.'
    }
    $weightTotal = 0.0
    foreach ($criterion in @($contract.rubric.criteria)) {
        if ([string]$criterion.criterion_id -notmatch '^[a-z0-9][a-z0-9._-]*$') {
            throw "Assessment Mastery criterion_id is not sanitized: $($criterion.criterion_id)"
        }
        if ([double]$criterion.max_score -le [double]$criterion.min_score) {
            throw "Assessment Mastery criterion score bounds are invalid: $($criterion.criterion_id)"
        }
        $weightTotal += [double]$criterion.mastery_weight
    }
    if ([Math]::Abs($weightTotal - 1.0) -gt 0.01) {
        throw "Assessment Mastery rubric weights must sum to 1.0, got $weightTotal."
    }
    if (@($contract.tasks).Count -lt 1) {
        throw 'Assessment Mastery contract must include at least one task.'
    }
    foreach ($task in @($contract.tasks)) {
        if ([string]$task.prompt_ref -notmatch '^prompt:[a-z0-9._:-]+$') {
            throw 'Assessment Mastery task must use prompt_ref instead of prompt body.'
        }
        if (@($task.expected_evidence_refs).Count -lt 1) {
            throw 'Assessment Mastery task must include expected evidence refs.'
        }
    }
    if ([double]$contract.mastery_model.mastery_threshold_percent -lt 1 -or [double]$contract.mastery_model.mastery_threshold_percent -gt 100) {
        throw 'Assessment Mastery mastery_threshold_percent must be between 1 and 100.'
    }
    if (@($contract.mastery_model.competency_refs).Count -lt 1) {
        throw 'Assessment Mastery contract must include competency refs.'
    }
    if ([string]$contract.feedback_policy.feedback_template_ref -notmatch '^feedback-template:[a-z0-9._:-]+$') {
        throw 'Assessment Mastery contract must use feedback_template_ref instead of feedback body.'
    }
    if ($contract.privacy_boundary.contains_learner_pii -ne $false) {
        throw 'Assessment Mastery contract must not contain learner PII.'
    }
    if ($contract.privacy_boundary.contains_submission_body -ne $false) {
        throw 'Assessment Mastery contract must not contain submission bodies.'
    }
    if ($contract.privacy_boundary.contains_private_feedback_body -ne $false) {
        throw 'Assessment Mastery contract must not contain private feedback bodies.'
    }
    if ($contract.privacy_boundary.contains_private_course_content -ne $false) {
        throw 'Assessment Mastery contract must not contain private course content.'
    }
    if ($contract.privacy_boundary.contains_absolute_path -ne $false) {
        throw 'Assessment Mastery contract must not contain absolute paths.'
    }
    if ($contract.privacy_boundary.logical_refs_only -ne $true) {
        throw 'Assessment Mastery contract must be logical refs only.'
    }
    if ($contractText -match '[A-Za-z]:\\') {
        throw 'Assessment Mastery contract must not contain absolute Windows paths.'
    }
    if ($contractText -match '(?i)Write an essay|full private essay|student@example.com|open-education-suite-private|api[_-]?key|bearer\s|secret\s*[:=]|token\s*[:=]') {
        throw 'Assessment Mastery contract leaked prompt text, private learner data, private paths, or credentials.'
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
    Assert-FileExists '.\subject-brains.json'
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
    Assert-FileExists '.\docs\subject-brain-federation.md'
    Assert-FileExists '.\docs\content-repo-readiness.md'
    Assert-FileExists '.\docs\teaching-quality-rubric.md'
    Assert-FileExists '.\docs\todo\TODO_12_generated_lecture_video.md'
    Assert-FileExists '.\docs\todo\TODO_21_generated_instructor_persona_contract.md'
    Assert-FileExists '.\docs\todo\TODO_22_subject_brain_federation.md'
    Assert-FileExists '.\schemas\adaptive-teacher.schema.json'
    Assert-FileExists '.\schemas\assessment.schema.json'
    Assert-FileExists '.\schemas\learner-state.schema.json'
    Assert-FileExists '.\schemas\ai-teacher.schema.json'
    Assert-FileExists '.\schemas\lecture-video.schema.json'
    Assert-FileExists '.\schemas\generated-instructor-persona.schema.json'
    Assert-FileExists '.\schemas\subject-brain.schema.json'
    Assert-FileExists '.\schemas\subject-brain-corpus.schema.json'
    Assert-FileExists '.\schemas\subject-brain-domain-cards.schema.json'
    Assert-FileExists '.\schemas\subject-brain-query.schema.json'
    Assert-FileExists '.\schemas\subject-brain-registry.schema.json'
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
    Assert-FileExists '.\fixtures\generated-instructor-persona.default.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\approved-male-calm-professor.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\approved-female-energetic-professor.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\approved-neutral-clear-coach.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\blocked\blocked-real-person-clone.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\blocked\blocked-voice-gender-mismatch.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\blocked\blocked-missing-disclosure.json'
    Assert-FileExists '.\fixtures\generated-instructor-personas\blocked\blocked-unapproved-consent.json'
    Assert-FileExists '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json'
    Assert-FileExists '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-rendered-media.json'
    Assert-FileExists '..\open-education-american-history\generated-lectures\amh-reference-intro\persona-reference.json'
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
    Assert-FileExists '.\scripts\teaching\export-voice-session-contract.ps1'
    Assert-FileExists '.\scripts\start_learner_ui_bridge.ps1'
    Assert-FileExists '.\scripts\manage_learner_ui_launcher.ps1'
    Assert-FileExists '.\scripts\export_local_app_launcher_manifest.ps1'
    Assert-FileExists '.\scripts\assessment\evaluate-answer.ps1'
    Assert-FileExists '.\scripts\assessment\export-assessment-mastery-contract.ps1'
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
    Assert-FileExists '.\scripts\quality\check-generated-instructor-persona.ps1'
    Assert-FileExists '.\scripts\quality\check-lecture-video.ps1'
    Assert-FileExists '.\scripts\quality\check-lecture-performance-promotion.ps1'
    Assert-FileExists '.\scripts\state\read-learner-state.ps1'
    Assert-FileExists '.\scripts\state\update-learner-state.ps1'
    Assert-FileExists '.\scripts\state\write-audit-report.ps1'
    Assert-FileExists '.\scripts\ai\build-teaching-prompt.ps1'
    Assert-FileExists '.\scripts\ai\invoke-openai-teacher.ps1'
    Assert-FileExists '.\scripts\ai\evaluate-model-output.ps1'
    Assert-FileExists '.\scripts\ai\subject_brain.py'
    Assert-FileExists '.\scripts\ai\subject-brain.ps1'
    Assert-FileExists '.\scripts\ai\extract_subject_pdf.py'
    Assert-FileExists '.\scripts\ai\invoke-local-teacher.ps1'
    Assert-FileExists '.\scripts\ai\build-content-ai-knowledge-federation.ps1'
    Assert-FileExists '.\generated\ai-knowledge\content-knowledge-catalog.json'
    Assert-FileExists '.\scripts\setup\build-planned-subject-brains.ps1'
    Assert-FileExists '..\open-education-teacher\selection\teacher-knowledge-routing-policy.json'
    Assert-FileExists '.\scripts\testing\run-live-gdev-teacher-smoke.ps1'
    Assert-FileExists '.\scripts\status\next-work.ps1'
    Assert-FileExists '.\ui\learner\index.html'
    Assert-FileExists '.\ui\learner\session-data.js'
    Assert-FileExists '.\ui\learner\styles.css'
    Assert-FileExists '.\ui\learner\app.js'
    Assert-FileExists '.\tests\learner-ui.spec.js'
    Assert-FileExists '.\tests\lecture-production-smoke.spec.js'
    Test-LocalAppLauncherManifest
    Test-VoiceStudioSessionContract
    Test-AssessmentMasteryContract

    $brainRegistryOutput = & .\scripts\ai\subject-brain.ps1 -Action validate-registry 2>&1
    $brainRegistryOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain registry validation failed with exit code $LASTEXITCODE."
    }
    $brainRegistry = ($brainRegistryOutput | Out-String) | ConvertFrom-Json
    if ($brainRegistry.errorCount -ne 0 -or $brainRegistry.activeBrainCount -lt 13 -or $brainRegistry.brainCount -lt 13) {
        throw 'Subject-brain registry must resolve all thirteen K-12 brain contracts.'
    }

    $locatorSelfTestOutput = & .\scripts\ai\subject-brain.ps1 -Action locator-self-test 2>&1
    $locatorSelfTestOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain locator self-test failed with exit code $LASTEXITCODE."
    }
    $locatorSelfTest = ($locatorSelfTestOutput | Out-String) | ConvertFrom-Json
    $requiredLocatorKinds = @('page', 'chapter', 'section', 'verse', 'equation', 'table', 'diagram', 'code-symbol', 'dataset', 'image', 'audiovisual-timestamp')
    $missingLocatorKinds = @($requiredLocatorKinds | Where-Object { $_ -notin @($locatorSelfTest.observedLocatorKinds) })
    if ($locatorSelfTest.passed -ne $true -or $locatorSelfTest.schemaVersion -ne 'open-education/subject-brain-locator/v1' -or $missingLocatorKinds.Count -ne 0 -or $locatorSelfTest.malformedChunkCount -ne 0) {
        throw "Subject-brain locator self-test did not prove all required structured locator kinds: $($missingLocatorKinds -join ', ')."
    }

    $retrievalSelfTestOutput = & .\scripts\ai\subject-brain.ps1 -Action retrieval-self-test 2>&1
    $retrievalSelfTestOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain hybrid retrieval self-test failed with exit code $LASTEXITCODE."
    }
    $retrievalSelfTest = ($retrievalSelfTestOutput | Out-String) | ConvertFrom-Json
    $failedRetrievalChecks = @($retrievalSelfTest.checks.PSObject.Properties | Where-Object { $_.Value -ne $true })
    if ($retrievalSelfTest.passed -ne $true -or $retrievalSelfTest.vectorAlgorithm -ne 'deterministic-hashed-concept-vector/v1' -or $retrievalSelfTest.vectorDimensions -ne 256 -or $failedRetrievalChecks.Count -ne 0) {
        throw "Subject-brain hybrid retrieval self-test failed checks: $($failedRetrievalChecks.Name -join ', ')."
    }

    $toolSelfTestOutput = & .\scripts\ai\subject-brain.ps1 -Action tool-self-test 2>&1
    $toolSelfTestOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain checked-tool self-test failed with exit code $LASTEXITCODE."
    }
    $toolSelfTest = ($toolSelfTestOutput | Out-String) | ConvertFrom-Json
    $requiredCheckedTools = @('calculator', 'symbolic-math', 'code-execution', 'data-analysis', 'mapping-timeline', 'citation-verification', 'source-comparison')
    $missingCheckedTools = @($requiredCheckedTools | Where-Object { $_ -notin @($toolSelfTest.capabilities) })
    $failedToolChecks = @($toolSelfTest.checks.PSObject.Properties | Where-Object { $_.Value -ne $true })
    if (
        $toolSelfTest.schemaVersion -ne 'open-education/subject-brain-tool-self-test/v1' -or
        $toolSelfTest.passed -ne $true -or
        $toolSelfTest.capabilityCount -ne 7 -or
        $missingCheckedTools.Count -ne 0 -or
        $failedToolChecks.Count -ne 0 -or
        $toolSelfTest.catalog.networkAccess -ne 'none' -or
        $toolSelfTest.catalog.durableLearnerStateMutationAllowed -ne $false -or
        $toolSelfTest.sampleResults.'code-execution'.result.arbitraryPythonAllowed -ne $false -or
        $toolSelfTest.sampleResults.'citation-verification'.result.claimEntailment -ne 'verified-exact-text' -or
        $toolSelfTest.sampleResults.'source-comparison'.result.truthAdjudicated -ne $false
    ) {
        throw "Subject-brain checked-tool self-test failed required capabilities or boundaries: missing=$($missingCheckedTools -join ', ') failed=$($failedToolChecks.Name -join ', ')."
    }

    $calculatorRequestPath = Join-Path $tmpRoot 'checked-calculator-request.json'
    [System.IO.File]::WriteAllText(
        $calculatorRequestPath,
        (@{
            schemaVersion = 'open-education/subject-brain-tool-request/v1'
            tool = 'calculator'
            expression = '250'
            unitConversion = @{
                from = 'cm'
                to = 'm'
            }
        } | ConvertTo-Json -Depth 10),
        [System.Text.UTF8Encoding]::new($false)
    )
    $calculatorOutput = & .\scripts\ai\subject-brain.ps1 -Action run-tool -RequestPath $calculatorRequestPath 2>&1
    $calculatorOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain checked calculator request failed with exit code $LASTEXITCODE."
    }
    $calculator = ($calculatorOutput | Out-String) | ConvertFrom-Json
    if (
        $calculator.schemaVersion -ne 'open-education/subject-brain-tool-result/v1' -or
        $calculator.status -ne 'passed' -or
        $calculator.result.unitConversion.exactValue -ne '5/2' -or
        $calculator.safety.retrievedProseTreatedAsComputation -ne $false
    ) {
        throw 'Subject-brain checked calculator did not return the exact unit conversion and safety contract.'
    }

    $domainCardSelfTestOutput = & .\scripts\ai\subject-brain.ps1 -Action domain-card-self-test 2>&1
    $domainCardSelfTestOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain domain-card self-test failed with exit code $LASTEXITCODE."
    }
    $domainCardSelfTest = ($domainCardSelfTestOutput | Out-String) | ConvertFrom-Json -Depth 50
    $requiredDomainCardTypes = @('argument', 'evidence-study', 'source-claim', 'equation-proof', 'experiment', 'historical-document', 'economic-claim', 'financial-scenario', 'code-api', 'health-safety', 'artwork-performance', 'practical-procedure')
    $missingDomainCardTypes = @($requiredDomainCardTypes | Where-Object { $_ -notin @($domainCardSelfTest.cardTypes) })
    $failedDomainCardChecks = @($domainCardSelfTest.checks.PSObject.Properties | Where-Object { $_.Value -ne $true })
    if (
        $domainCardSelfTest.schemaVersion -ne 'open-education/subject-brain-domain-card-self-test/v1' -or
        $domainCardSelfTest.passed -ne $true -or
        $domainCardSelfTest.cardTypeCount -ne 12 -or
        $missingDomainCardTypes.Count -ne 0 -or
        $failedDomainCardChecks.Count -ne 0 -or
        $domainCardSelfTest.validResult.boundaries.citationsRequired -ne $true -or
        $domainCardSelfTest.validResult.boundaries.uncertaintyAndLimitsRequired -ne $true -or
        $domainCardSelfTest.validResult.boundaries.privateFinancialDataAllowed -ne $false -or
        $domainCardSelfTest.validResult.boundaries.healthDiagnosisAllowed -ne $false -or
        $domainCardSelfTest.validResult.boundaries.professionalReviewPreserved -ne $true -or
        $domainCardSelfTest.validResult.boundaries.durableLearnerStateMutationAllowed -ne $false
    ) {
        throw "Subject-brain domain-card self-test failed required types or boundaries: missing=$($missingDomainCardTypes -join ', ') failed=$($failedDomainCardChecks.Name -join ', ')."
    }
    $domainCardSamplePath = Join-Path $tmpRoot 'subject-brain-domain-cards.sample.json'
    [System.IO.File]::WriteAllText(
        $domainCardSamplePath,
        ($domainCardSelfTest.sampleDocument | ConvertTo-Json -Depth 50),
        [System.Text.UTF8Encoding]::new($false)
    )
    $domainCardValidationOutput = & .\scripts\ai\subject-brain.ps1 -Action validate-domain-cards -CardsPath $domainCardSamplePath 2>&1
    $domainCardValidationOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain domain-card validation action failed with exit code $LASTEXITCODE."
    }
    $domainCardValidation = ($domainCardValidationOutput | Out-String) | ConvertFrom-Json -Depth 30
    if (
        $domainCardValidation.schemaVersion -ne 'open-education/subject-brain-domain-card-validation/v1' -or
        $domainCardValidation.passed -ne $true -or
        $domainCardValidation.cardCount -ne 12 -or
        $domainCardValidation.cardTypeCount -ne 12 -or
        @($domainCardValidation.errors).Count -ne 0
    ) {
        throw 'Subject-brain domain-card validation action did not accept the exact twelve-type exemplar.'
    }

    $brainPlanOutput = & .\scripts\ai\subject-brain.ps1 -Action plan-query -RegistryPath '.\subject-brains.json' -Question 'compare biblical teaching with psychological learning science and memory' -GradeBand '9-12' -Limit 3 2>&1
    $brainPlanOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Cross-brain query planning failed with exit code $LASTEXITCODE."
    }
    $brainPlan = ($brainPlanOutput | Out-String) | ConvertFrom-Json
    $plannedBrainIds = @($brainPlan.plans.brainId)
    if (
        $brainPlan.schemaVersion -ne 'open-education/subject-brain-query-plan/v1' -or
        $brainPlan.plannedBrainCount -lt 2 -or
        'biblical-theological-literacy' -notin $plannedBrainIds -or
        'psychology-learning-science' -notin $plannedBrainIds -or
        $brainPlan.routingPolicy.offlineLexicalFallbackAvailable -ne $true -or
        $brainPlan.routingPolicy.durableLearnerStateMutationAllowed -ne $false
    ) {
        throw 'Cross-brain planner did not route the mixed-domain question to both required specialist brains.'
    }

    $criticalBrainRoot = Resolve-Path -LiteralPath '..\critical-thinking-ai-tool'
    $criticalIndexPath = Join-Path $tmpRoot 'critical-thinking-subject-brain.sqlite'
    $criticalIndexOutput = & .\scripts\ai\subject-brain.ps1 -Action index -BrainRoot $criticalBrainRoot.Path -IndexPath $criticalIndexPath 2>&1
    $criticalIndexOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Critical-thinking subject-brain indexing failed with exit code $LASTEXITCODE."
    }
    $criticalIndex = ($criticalIndexOutput | Out-String) | ConvertFrom-Json
    if (
        $criticalIndex.brainId -ne 'critical-thinking' -or
        $criticalIndex.indexedSourceCount -lt 3 -or
        $criticalIndex.chunkCount -lt 100 -or
        $criticalIndex.locatorSchemaVersion -ne 'open-education/subject-brain-locator/v1' -or
        @($criticalIndex.locatorKindCounts.PSObject.Properties).Count -lt 1 -or
        $criticalIndex.retrievalMode -ne 'hybrid-lexical-vector' -or
        $criticalIndex.vectorAlgorithm -ne 'deterministic-hashed-concept-vector/v1' -or
        $criticalIndex.vectorDimensions -ne 256 -or
        $criticalIndex.lexicalFallbackAvailable -ne $true
    ) {
        throw 'Critical-thinking subject-brain index does not contain the checked Open Logic starter corpus.'
    }

    $brainQueryOutput = & .\scripts\ai\subject-brain.ps1 -Action query -IndexPath $criticalIndexPath -Question 'valid deductive argument premises conclusion' -GradeBand '9-12' -Limit 5 2>&1
    $brainQueryOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain query failed with exit code $LASTEXITCODE."
    }
    $brainQueryText = $brainQueryOutput | Out-String
    $brainQuery = $brainQueryText | ConvertFrom-Json
    if (
        $brainQuery.retrievalOnly -ne $true -or
        $brainQuery.resultCount -lt 1 -or
        $null -ne $brainQuery.generatedAnswer -or
        $brainQuery.retrievalModeUsed -ne 'hybrid-lexical-vector' -or
        $brainQuery.lexicalFallbackAvailable -ne $true -or
        $brainQuery.rankingPolicy.lexicalAndVectorSignalsCombined -ne $true -or
        $brainQuery.rankingPolicy.evidenceStrengthIncluded -ne $true -or
        $brainQuery.rankingPolicy.exactDuplicatesSuppressed -ne $true -or
        $brainQuery.coverage.diversificationApplied -ne $true
    ) {
        throw 'Subject-brain query must return retrieval-only context without a generated answer.'
    }
    $openLogicResults = @($brainQuery.results | Where-Object { $_.sourceId -eq 'open-logic-complete-2026-07-12' })
    if ($openLogicResults.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$openLogicResults[0].locator) -or [string]::IsNullOrWhiteSpace([string]$openLogicResults[0].locatorKind) -or $openLogicResults[0].locatorData.schemaVersion -ne 'open-education/subject-brain-locator/v1' -or $openLogicResults[0].locatorData.charStart -lt 1 -or $openLogicResults[0].locatorData.charEnd -lt $openLogicResults[0].locatorData.charStart) {
        throw 'Subject-brain query did not retain an exact structured Open Logic locator.'
    }
    $malformedHybridResults = @($brainQuery.results | Where-Object {
        [double]$_.retrievalScore -le 0 -or
        [string]::IsNullOrWhiteSpace([string]$_.evidenceTier) -or
        $null -eq $_.scoreBreakdown -or
        $null -eq $_.retrievalSignals
    })
    if ($malformedHybridResults.Count -ne 0 -or @($brainQuery.results | Where-Object { $_.retrievalSignals.vectorMatched -eq $true }).Count -lt 1) {
        throw 'Hybrid subject-brain query did not retain vector, evidence-strength, and reranking signals.'
    }

    $lexicalFallbackOutput = & .\scripts\ai\subject-brain.ps1 -Action query -IndexPath $criticalIndexPath -Question 'valid deductive argument premises conclusion' -GradeBand '9-12' -Limit 3 -RetrievalMode lexical 2>&1
    $lexicalFallbackOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain lexical fallback query failed with exit code $LASTEXITCODE."
    }
    $lexicalFallback = ($lexicalFallbackOutput | Out-String) | ConvertFrom-Json
    if (
        $lexicalFallback.retrievalModeUsed -ne 'lexical-fts' -or
        $lexicalFallback.lexicalFallbackAvailable -ne $true -or
        $lexicalFallback.resultCount -lt 1 -or
        $null -ne $lexicalFallback.vectorAlgorithm -or
        @($lexicalFallback.results | Where-Object { $_.retrievalSignals.vectorMatched -ne $false }).Count -ne 0
    ) {
        throw 'Subject-brain lexical-only fallback contract is not operational.'
    }

    $brainQueryPath = Join-Path $tmpRoot 'critical-thinking-query.json'
    Set-Content -LiteralPath $brainQueryPath -Value $brainQueryText
    $groundedPromptOutput = & .\scripts\ai\build-teaching-prompt.ps1 -SubjectBrainResultsPath $brainQueryPath 2>&1
    $groundedPromptOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain teaching prompt build failed with exit code $LASTEXITCODE."
    }
    $groundedPrompt = ($groundedPromptOutput | Out-String) | ConvertFrom-Json
    if ($groundedPrompt.subjectBrainContext.brainId -ne 'critical-thinking' -or @($groundedPrompt.subjectBrainContext.results).Count -lt 1) {
        throw 'Teaching prompt did not retain specialist subject-brain context.'
    }
    if ('subject_brain.query' -notin @($groundedPrompt.tools)) {
        throw 'Teaching prompt tool contract is missing subject_brain.query.'
    }

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

    & .\scripts\ai\build-content-ai-knowledge-federation.ps1 -Check 2>&1 | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Content AI knowledge federation check failed with exit code $LASTEXITCODE."
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

    $generatedInstructorPersonaOutput = & .\scripts\quality\check-generated-instructor-persona.ps1 -SelfTest 2>&1
    $generatedInstructorPersonaOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Generated instructor persona contract check failed with exit code $LASTEXITCODE."
    }
    $generatedInstructorPersonaResult = $generatedInstructorPersonaOutput | ConvertFrom-Json
    if ($generatedInstructorPersonaResult.errorCount -ne 0) {
        throw 'Generated instructor persona contract check reported errors.'
    }
    if ($generatedInstructorPersonaResult.readOnly -ne $true -or $generatedInstructorPersonaResult.networkAccess -ne 'none') {
        throw 'Generated instructor persona contract check must be read-only and offline-safe by default.'
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
