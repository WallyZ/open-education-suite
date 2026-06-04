[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-CheckError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

$errors = [System.Collections.Generic.List[string]]::new()
$uiRoot = '.\ui\learner'
$indexPath = Join-Path $uiRoot 'index.html'
$stylePath = Join-Path $uiRoot 'styles.css'
$scriptPath = Join-Path $uiRoot 'app.js'
$dataPath = Join-Path $uiRoot 'session-data.js'
$localePath = Join-Path (Join-Path $uiRoot 'locales') 'en.js'
$testPath = '.\tests\learner-ui.spec.js'

foreach ($path in @($indexPath, $stylePath, $scriptPath, $dataPath, $localePath, $testPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-CheckError $errors "Missing learner UI file: $path"
    }
}

if ($errors.Count -eq 0) {
    $html = Get-Content -LiteralPath $indexPath -Raw
    $css = Get-Content -LiteralPath $stylePath -Raw
    $js = Get-Content -LiteralPath $scriptPath -Raw
    $data = Get-Content -LiteralPath $dataPath -Raw
    $locale = Get-Content -LiteralPath $localePath -Raw
    $tests = Get-Content -LiteralPath $testPath -Raw

    foreach ($required in @(
        '<main id="workspace"',
        'id="runSessionButton"',
        'id="sessionBridgeLog"',
        'id="liveTeacherButton"',
        'id="liveTeacherLog"',
        'src="locales/en.js"',
        'data-l10n="labels.workspaceTitle"',
        'src="session-data.js"',
        'id="sourceSelect"',
        'id="courseSelect"',
        'id="objectiveList"',
        'Course navigation',
        'id="analyticsSummary"',
        'id="analyticsEvidenceList"',
        'No clickstream or time-spent tracking',
        'data-view="handoff"',
        'id="handoffBlockers"',
        'id="handoffInterventions"',
        'id="contentHealthList"',
        'Operator review only. No learner-state mutation.',
        'aria-live="polite"',
        'class="skip-link"',
        'data-view="lesson"',
        'data-view="lecture"',
        'data-view="progress"',
        'data-view="assessment"',
        'data-view="evidence"',
        'id="lectureProgress"',
        'id="lectureFrame"',
        'id="lectureTranscript"',
        'id="lectureCheckpoints"',
        'id="pausePromptList"',
        'id="assessmentModeControls"',
        'id="assessmentRenderSurface"',
        'id="saveAssessmentButton"',
        'id="saveStateButton"',
        'id="stateExchange"',
        'id="syncPreviewButton"',
        'id="learnerResponse"',
        'id="journalEntry"',
        'GDEV-101 Game Design Foundations'
    )) {
        if ($html -notlike "*$required*") {
            Add-CheckError $errors "Learner UI index missing marker: $required"
        }
    }

    foreach ($required in @(
        ':focus-visible',
        '@media (max-width: 980px)',
        '@media (prefers-reduced-motion: reduce)',
        '.workspace-grid',
        '.course-browser',
        '.objective-chip',
        '.analytics-panel',
        '.analytics-card',
        '.handoff-grid',
        '.handoff-column',
        '.lecture-layout',
        '.lecture-frame',
        '.lecture-video',
        '.lecture-pause-overlay',
        '.pause-prompt-list',
        '.pause-prompt-button',
        '.lecture-media-meta',
        '.checkpoint-card',
        '.assessment-mode-controls',
        '.assessment-card',
        '.assessment-option',
        '.state-panel',
        '.is-high-contrast',
        '.is-focus'
    )) {
        if ($css -notlike "*$required*") {
            Add-CheckError $errors "Learner UI styles missing marker: $required"
        }
    }

    foreach ($required in @(
        'window.openEducationSessionOutput',
        'window.openEducationLecturePackage',
        'openEducationLocale',
        'localeConfig',
        'function applyLocalizedLabels',
        'function formatLocaleDate',
        'function feedbackText',
        'window.openEducationContentCatalog',
        'currentContentCatalog',
        'function buildSessionFromStartSession',
        'function renderCourseNavigation',
        'function renderLearnerAnalytics',
        'function renderOperatorHandoff',
        'function normalizeLecture',
        'function mediaPathToUrl',
        'function renderLectureMediaFrame',
        'function renderLecturePauseOverlay',
        'function renderPausePromptList',
        'function getActivePausePrompt',
        'function updateLecturePositionFromVideo',
        'lectureVideo',
        'function runDeterministicSessionTurn',
        'function refreshLiveTeacherStatus',
        'function invokeLiveTeacher',
        'openEducationLearnerState',
        'function saveLearnerState',
        'function exportLearnerState',
        'function importLearnerState',
        'function previewLearnerStateSync',
        'assessmentModes',
        'function renderAssessment',
        'function saveAssessmentEvidence',
        'openEducationAssessmentEvidence',
        'multiple-choice',
        'short-answer',
        'project-rubric',
        'oral-explained-answer',
        'append-events-and-recompute-mastery',
        '/api/session/start',
        '/api/teacher/live',
        'Live AI teacher disabled by operator setting.',
        'openEducationLearnerJournal',
        'openEducationLectureResume',
        'openEducationLectureCheckpoints',
        'localStorage',
        'function renderLecture',
        'function setLecturePosition',
        'function saveCheckpoint',
        'function appendCheckpointEvidenceToLearnerState',
        'lecture_checkpoint_submitted',
        'masteryImpact: evidence.masteryImpact',
        'function submitResponse',
        'function showHint',
        'function markComplete'
    )) {
        if ($js -notlike "*$required*") {
            Add-CheckError $errors "Learner UI script missing marker: $required"
        }
    }

    foreach ($required in @(
        'window.openEducationSessionOutput',
        'window.openEducationLecturePackage',
        'window.openEducationContentCatalog',
        'game-development:objectives/course/gdev-102/programming-fundamentals',
        'game-development:objectives/course/gdev-101/design-vocabulary',
        'study-plans\\courses\\GDEV-101-game-design-foundations.md',
        'lecture-video:gdev-101-design-vocabulary-short',
        'learnerProfile',
        'sourceProvenance'
    )) {
        if ($data -notlike "*$required*") {
            Add-CheckError $errors "Learner UI session data missing marker: $required"
        }
    }

    foreach ($required in @(
        'window.openEducationLocale',
        'locale: "en-US"',
        'dateStyle: "medium"',
        'objectiveNames',
        'feedback',
        'Assessment response saved locally as an evidence proposal.',
        'Checkpoint saved to learner state as an evidence proposal.'
    )) {
        if ($locale -notlike "*$required*") {
            Add-CheckError $errors "Learner UI locale missing marker: $required"
        }
    }

    foreach ($required in @(
        'supports keyboard flow across all learner workspace views',
        'deterministic visual regression contract',
        'learner-visual-regression-contract',
        'hasHorizontalOverflow',
        'page.screenshot'
    )) {
        if ($tests -notlike "*$required*") {
            Add-CheckError $errors "Learner UI Playwright test missing marker: $required"
        }
    }
}

[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    errorCount = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 8

if ($errors.Count -gt 0) {
    exit 1
}

exit 0
