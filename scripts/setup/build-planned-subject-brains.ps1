[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$suiteRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $suiteRoot
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

$definitions = @(
    [ordered]@{
        BrainId = 'language-literature-rhetoric'
        RepoName = 'language-literature-rhetoric-ai-tool'
        Title = 'Language, Literature, Composition, Rhetoric, And Classics'
        Description = 'Rights-gated retrieval contracts for reading, language, composition, literary study, rhetoric, classics, and world languages.'
        Tags = @('reading', 'literature', 'composition', 'grammar', 'rhetoric', 'classics', 'world-languages')
        OutputTypes = @('grounded-passage', 'textual-analysis-context', 'composition-context', 'tradition-comparison-context')
        Escalation = @('self-harm', 'abuse', 'sexual content involving minors', 'graphic violence', 'hate material', 'compelled belief')
    },
    [ordered]@{
        BrainId = 'mathematics'
        RepoName = 'mathematics-ai-tool'
        Title = 'Mathematics, Statistics, And Quantitative Reasoning'
        Description = 'Rights-gated retrieval contracts for arithmetic, algebra, geometry, trigonometry, calculus, statistics, proof, and mathematical modeling.'
        Tags = @('arithmetic', 'algebra', 'geometry', 'trigonometry', 'calculus', 'statistics', 'proof')
        OutputTypes = @('grounded-passage', 'definition-context', 'worked-example-context', 'proof-context')
        Escalation = @('individualized financial advice', 'unsafe engineering calculation', 'high-stakes medical calculation', 'assessment cheating')
    },
    [ordered]@{
        BrainId = 'science-engineering'
        RepoName = 'science-engineering-ai-tool'
        Title = 'Physical, Life, Earth, Space Science, And Engineering'
        Description = 'Rights-gated retrieval contracts for physical, life, earth, and space science plus engineering design and laboratory practice.'
        Tags = @('physics', 'chemistry', 'biology', 'earth-science', 'astronomy', 'engineering')
        OutputTypes = @('grounded-passage', 'evidence-context', 'experiment-context', 'engineering-context')
        Escalation = @('dangerous experiment', 'weapon construction', 'biohazard', 'chemical exposure', 'medical advice', 'environmental emergency')
    },
    [ordered]@{
        BrainId = 'history-civics-geography-law'
        RepoName = 'history-civics-geography-law-ai-tool'
        Title = 'History, Civics, Government, Geography, And Law'
        Description = 'Rights-gated retrieval contracts for historical inquiry, primary sources, civics, government, geography, and legal literacy.'
        Tags = @('history', 'civics', 'government', 'geography', 'law', 'primary-sources')
        OutputTypes = @('grounded-passage', 'primary-source-context', 'claim-comparison-context', 'timeline-context')
        Escalation = @('individualized legal advice', 'current emergency', 'political persuasion targeting', 'extremist recruitment', 'compelled political confession')
    },
    [ordered]@{
        BrainId = 'economics-finance-business'
        RepoName = 'economics-finance-business-ai-tool'
        Title = 'Economics, Personal Finance, Investing, Accounting, Business, Sales, And Negotiation'
        Description = 'Rights-gated retrieval contracts for economics, personal finance, investing, accounting, business, ethical sales, and negotiation.'
        Tags = @('economics', 'personal-finance', 'investing', 'accounting', 'business', 'sales', 'negotiation')
        OutputTypes = @('grounded-passage', 'economic-claim-context', 'financial-scenario-context', 'business-practice-context')
        Escalation = @('individualized financial advice', 'fraud', 'tax or legal advice', 'coercive sales', 'gambling', 'market manipulation')
    },
    [ordered]@{
        BrainId = 'computing-data-cyber'
        RepoName = 'computing-data-cyber-ai-tool'
        Title = 'Computing, Software, Data Science, AI Literacy, And Cybersecurity'
        Description = 'Rights-gated retrieval contracts for computing, software engineering, data science, AI literacy, cybersecurity, and digital citizenship.'
        Tags = @('computer-science', 'software-development', 'data-science', 'ai-literacy', 'cybersecurity', 'digital-citizenship')
        OutputTypes = @('grounded-passage', 'code-context', 'api-context', 'security-context')
        Escalation = @('credential theft', 'malware', 'unauthorized access', 'privacy invasion', 'dangerous automation', 'academic cheating')
    },
    [ordered]@{
        BrainId = 'health-fitness-safety'
        RepoName = 'health-fitness-safety-ai-tool'
        Title = 'Health, Fitness, Nutrition, Safety, And First Aid'
        Description = 'Rights-gated retrieval contracts for health literacy, fitness, nutrition, sleep, safety, risk reduction, and first aid.'
        Tags = @('health', 'fitness', 'nutrition', 'sleep', 'safety', 'first-aid')
        OutputTypes = @('grounded-passage', 'health-guidance-context', 'safety-procedure-context', 'evidence-context')
        Escalation = @('medical emergency', 'self-harm', 'abuse', 'eating disorder', 'diagnosis', 'treatment', 'medication', 'dangerous exercise')
    },
    [ordered]@{
        BrainId = 'arts-music-design-performance'
        RepoName = 'arts-music-design-performance-ai-tool'
        Title = 'Visual Arts, Music, Design, Theater, Dance, And Performance'
        Description = 'Rights-gated retrieval contracts for visual art, music, design, theater, dance, art history, and performance practice.'
        Tags = @('visual-art', 'music', 'design', 'theater', 'dance', 'performance')
        OutputTypes = @('grounded-passage', 'artwork-context', 'performance-context', 'design-context')
        Escalation = @('copyright infringement', 'unsafe performance', 'sexual content involving minors', 'graphic content', 'harassment', 'compelled expression')
    },
    [ordered]@{
        BrainId = 'human-relations-leadership'
        RepoName = 'human-relations-leadership-ai-tool'
        Title = 'Communication, Relationships, Leadership, Ethics, And Conflict Resolution'
        Description = 'Rights-gated retrieval contracts for communication, friendship, family, relationships, leadership, ethics, service, and conflict resolution.'
        Tags = @('communication', 'relationships', 'leadership', 'ethics', 'conflict-resolution', 'social-confidence')
        OutputTypes = @('grounded-passage', 'relationship-scenario-context', 'ethical-decision-context', 'conflict-context')
        Escalation = @('abuse', 'coercion', 'stalking', 'sexual exploitation', 'self-harm', 'violence', 'crisis counseling', 'compelled belief')
    },
    [ordered]@{
        BrainId = 'practical-life-career-home'
        RepoName = 'practical-life-career-home-ai-tool'
        Title = 'Practical Life, Career, Home, Consumer, And Emergency Readiness'
        Description = 'Rights-gated retrieval contracts for career preparation, household capability, consumer skills, maintenance, projects, and emergency readiness.'
        Tags = @('career', 'home-economics', 'consumer-skills', 'maintenance', 'emergency-readiness', 'project-management')
        OutputTypes = @('grounded-passage', 'practical-procedure-context', 'consumer-context', 'career-context')
        Escalation = @('active emergency', 'dangerous repair', 'electrical or gas hazard', 'legal advice', 'medical advice', 'financial exploitation')
    }
)

function Write-Utf8File {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    [System.IO.File]::WriteAllText(
        $Path,
        ($Content.TrimEnd() + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
}

$agentsTemplate = @'
# AGENTS.md

## Mission

Maintain the {{TITLE}} specialist subject brain as a local-first,
provenance-first evidence service for Open Education.

## Boundaries

- This repo owns its subject manifest, evidence policy, corpus plan, and source inventory.
- `F:\dev\open-education-suite` owns generic indexing, retrieval, teacher orchestration, learner state, and provider adapters.
- Every indexed source requires an exact edition, canonical route, local-use rights decision, and checksum.
- Course objectives and reviewed lesson content remain authoritative; retrieved context is supplemental evidence.
- Separate facts, interpretation, application, and personal conviction.
- Optional Christian formation routes may use appropriate evidence without compelling belief; equivalent non-devotional academic routes remain available.
- Do not store learner PII, private journals, credentials, or raw learner transcripts.

## Verification

Use exactly:

```powershell
.\scripts\codex-verify.ps1
```
'@

$readmeTemplate = @'
# {{TITLE}} Subject Brain

This local-first repository implements the Open Education specialist
subject-brain contract for {{DESCRIPTION}}

## Current Readiness

`contract-ready` means the manifest, corpus ledger, evidence policy, corpus
plan, rights gates, and repo-local verification are present. It does not mean
that a usable corpus has been acquired, that learner queries are enabled, or
that the brain is pilot- or production-ready. The suite must use reviewed
deterministic lesson content until this repo reaches at least
`starter-corpus-ready`.

```powershell
.\scripts\codex-verify.ps1
.\scripts\subject-brain.ps1 -Action validate
```

## Evidence And Formation

The brain returns cited retrieval context only; it never writes learner state
or silently replaces a course objective, assessment, source boundary, or
teacher-reviewed answer. Claims must distinguish evidence from interpretation
and uncertainty.

Christianity, faith, family, service, vocation, stewardship, and Christian
virtue may be encouraged through course-selected optional formation routes.
No learner must profess a belief. Equivalent non-devotional academic work
remains available, and belief-laden questions preserve tradition and viewpoint
labels.

## Corpus Boundary

Downloaded and derived payloads under `data/source-files/` stay local and are
excluded from Git. Version control contains planning metadata, exact source
and alternate routes, edition notes, rights and AI-ingestion decisions,
checksums after acquisition, accessibility status, and refresh records. A
source may be indexed only after its item-level record is approved and its
local checksum matches.
'@

$evidencePolicyTemplate = @'
# Evidence Policy

## Scope

This policy governs evidence used by the {{TITLE}} subject brain.

## Ranking And Presentation

1. Prefer primary sources, official records, standards, and strong systematic evidence when appropriate to the claim.
2. Preserve exact editions, dates, authorship, locators, and source limitations.
3. Label source type, evidence strength, uncertainty, disagreement, and material conflicts.
4. Steelman credible opposing interpretations before critique.
5. Separate facts, interpretation, application, and personal conviction.
6. Never treat citation presence as proof that the citation entails the claim.
7. Do not infer redistribution or AI-ingestion permission from public access or local possession.

## Learner And Formation Boundaries

- Course-owned objectives, deterministic explanations, and reviewed answer keys remain authoritative.
- Retrieved passages are supplemental context, not an automatically correct answer.
- Christian formation routes may be encouraged when selected by the course or family, without compelled profession.
- Equivalent non-devotional academic routes must remain available.
- Age band, accessibility needs, source restrictions, and human-escalation topics are enforced before use.
- The brain never stores learner PII or mutates durable learner state.

## Promotion

`contract-ready` permits metadata and contract review only. Promotion requires
at least one rights-approved, checksum-verified local source plus grade-banded
retrieval, citation, age-fit, accessibility, conflict, refusal, and tutor
transcript evidence. Qualified external review and real learner evidence are
required before `production-ready`.
'@

$corpusPlanTemplate = @'
# Corpus Plan

## Purpose

Build a rights-safe, grade-banded corpus for {{TITLE}} without treating
downloadability, local possession, or a broad license label as permission to
index or redistribute a specific edition.

## Planned Coverage

Initial subject tags: {{TAGS}}.

Each acquisition tranche must record:

- exact title, author or issuing body, edition or release, publication date, and stable locator;
- canonical URL, alternate route, retrieval date, and SHA-256 checksum;
- copyright, license, classroom-use, local-indexing, AI-ingestion, adaptation, and redistribution decisions;
- grade bands, topics, evidence tier, viewpoint or tradition labels, accessibility, and refresh trigger;
- extraction method and locators appropriate to pages, sections, tables, figures, equations, code, media, or primary sources.

## Staged Readiness

1. Review candidate metadata and rights before download.
2. Acquire only approved items into the ignored `data/source-files/` boundary.
3. Verify checksums and extraction quality.
4. Add grade-banded gold questions and restricted-source refusal tests.
5. Review tutor transcripts and deterministic fallbacks.
6. Require qualified subject, pedagogy, accessibility, safety, and rights review before production use.

The generated planning record in `data/corpus-manifest.json` is not subject
evidence and is not indexable. The suite must fall back to reviewed course
content while no approved local source exists.
'@

$licenseText = @'
# License

Repo-authored manifests, source inventories, policies, and documentation are
licensed under CC BY 4.0.

Downloaded books, papers, datasets, media, and other third-party sources retain
their own licenses. Each source's item-level rights and provenance record
controls its use; this repo license never overrides a third-party license.
'@

$ignoreText = @'
.codex-cache/
.local/
.venv/
__pycache__/
*.py[cod]
*.sqlite
*.sqlite-shm
*.sqlite-wal

# Downloaded and derived corpus payloads stay local. Metadata and the directory
# placeholder remain version-controlled.
data/source-files/*
!data/source-files/.gitkeep
'@

$wrapperText = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('validate', 'index', 'query')]
    [string]$Action,
    [string]$IndexPath = '.\.local\subject-brain.sqlite',
    [string]$Question = '',
    [ValidateSet('', 'K-2', '3-5', '6-8', '9-12', 'adult')]
    [string]$GradeBand = '',
    [switch]$Replace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$suiteScript = Join-Path (Join-Path $repo '..\open-education-suite') 'scripts\ai\subject-brain.ps1'
if (-not (Test-Path -LiteralPath $suiteScript -PathType Leaf)) {
    throw "Missing suite subject-brain adapter: $suiteScript"
}

switch ($Action) {
    'validate' { & $suiteScript -Action validate-brain -BrainRoot $repo }
    'index' { & $suiteScript -Action index -BrainRoot $repo -IndexPath $IndexPath -Replace:$Replace }
    'query' { & $suiteScript -Action query -IndexPath $IndexPath -Question $Question -GradeBand $GradeBand }
}
exit $LASTEXITCODE
'@

$verifyTemplate = @'
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runId = ('{0:yyyyMMdd_HHmmss}_{1}' -f (Get-Date), [Guid]::NewGuid().ToString('N').Substring(0, 8))
$cacheRoot = Join-Path $repo '.codex-cache'
$logRoot = Join-Path $cacheRoot 'logs'
$tmpRoot = Join-Path (Join-Path $cacheRoot 'tmp') $runId
$logPath = Join-Path $logRoot ("codex-verify_{0}.log" -f $runId)
[void](New-Item -ItemType Directory -Force -Path $logRoot, $tmpRoot)

$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$exitCode = 1
$locationPushed = $false

function Write-VerifyLog([string]$Message) {
    $Message | Tee-Object -FilePath $script:logPath -Append
}

try {
    $env:TEMP = $tmpRoot
    $env:TMP = $tmpRoot
    Push-Location $repo
    $locationPushed = $true

    foreach ($path in @(
        '.\AGENTS.md', '.\README.md', '.\LICENSE.md', '.\.gitignore',
        '.\subject-brain.json', '.\data\corpus-manifest.json',
        '.\data\source-files\.gitkeep', '.\docs\CORPUS_PLAN.md',
        '.\docs\EVIDENCE_POLICY.md', '.\scripts\subject-brain.ps1'
    )) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing required file: $path"
        }
        Write-VerifyLog "ok file $path"
    }

    $localPayloads = @(
        Get-ChildItem -LiteralPath '.\data\source-files' -File -Recurse |
            Where-Object { $_.Name -ne '.gitkeep' }
    )
    if ($localPayloads.Count -ne 0) {
        throw 'A contract-ready scaffold must not contain downloaded corpus payloads.'
    }

    $validationOutput = & .\scripts\subject-brain.ps1 -Action validate 2>&1
    $validationOutput | Tee-Object -FilePath $logPath -Append
    if ($LASTEXITCODE -ne 0) {
        throw "Subject-brain validation failed with exit code $LASTEXITCODE."
    }
    $validation = ($validationOutput | Out-String) | ConvertFrom-Json
    if (
        $validation.brainId -ne '{{BRAIN_ID}}' -or
        $validation.status -ne 'contract-ready' -or
        $validation.errorCount -ne 0 -or
        $validation.sourceCount -lt 1 -or
        $validation.localReadyCount -ne 0
    ) {
        throw 'Subject-brain validation returned an invalid contract-ready scaffold.'
    }

    Write-VerifyLog '{{BRAIN_ID}} contract-ready subject-brain verification passed.'
    $exitCode = 0
}
catch {
    Write-VerifyLog ("codex-verify failed: {0}" -f $_.Exception.Message)
    $exitCode = 1
}
finally {
    if ($locationPushed) { Pop-Location }
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($exitCode -ne 0) {
    Write-Output ("codex-verify failed: exit={0} log={1}" -f $exitCode, $logPath)
    exit $exitCode
}
Write-Output ("codex-verify passed: log={0}" -f $logPath)
exit 0
'@

$created = @()
foreach ($definition in $definitions) {
    $target = Join-Path $WorkspaceRoot $definition.RepoName
    if (Test-Path -LiteralPath $target) {
        throw "Refusing to overwrite existing subject-brain directory: $target"
    }
    if (-not $PSCmdlet.ShouldProcess($target, 'Create contract-ready subject-brain repository scaffold')) {
        continue
    }

    foreach ($directory in @(
        $target,
        (Join-Path $target 'data\source-files'),
        (Join-Path $target 'docs'),
        (Join-Path $target 'scripts')
    )) {
        [void](New-Item -ItemType Directory -Force -Path $directory)
    }

    $manifest = [ordered]@{
        schemaVersion = 'open-education/subject-brain/v1'
        brainId = $definition.BrainId
        title = $definition.Title
        role = 'specialist-subject-brain'
        status = 'contract-ready'
        description = $definition.Description
        subjectTags = $definition.Tags
        gradeBands = @('K-2', '3-5', '6-8', '9-12')
        capabilities = [ordered]@{
            ingestionFormats = @('txt', 'markdown', 'html', 'json', 'csv', 'pdf', 'docx', 'epub')
            retrievalModes = @('lexical-fts')
            outputTypes = $definition.OutputTypes
        }
        paths = [ordered]@{
            corpusManifest = 'data/corpus-manifest.json'
            evidencePolicy = 'docs/EVIDENCE_POLICY.md'
            corpusPlan = 'docs/CORPUS_PLAN.md'
        }
        rightsPolicy = [ordered]@{
            requiredRightsStatus = 'approved-for-local-index'
            checksumRequired = $true
            unknownRightsBehavior = 'block-indexing'
            restrictedTextBehavior = 'metadata-only'
        }
        queryPolicy = [ordered]@{
            citationRequired = $true
            locatorRequired = $true
            uncertaintyRequired = $true
            conflictDisclosureRequired = $true
            answerGenerationMode = 'retrieval-context-only'
        }
        safetyPolicy = [ordered]@{
            learnerPrivateDataAllowed = $false
            durableStateMutationAllowed = $false
            ageBandRequired = $true
            humanEscalationTopics = $definition.Escalation
        }
    }

    $corpus = [ordered]@{
        schemaVersion = 'open-education/subject-brain-corpus/v1'
        brainId = $definition.BrainId
        updatedAt = '2026-07-23'
        sources = @(
            [ordered]@{
                sourceId = "$($definition.BrainId)-corpus-plan-v1"
                title = "$($definition.Title) Corpus Acquisition Plan"
                sourceType = 'repo-policy'
                canonicalUrl = "https://github.com/WallyZ/$($definition.RepoName)/blob/main/docs/CORPUS_PLAN.md"
                alternateUrls = @()
                localPath = $null
                sha256 = $null
                gradeBands = @('K-2', '3-5', '6-8', '9-12')
                topics = $definition.Tags
                evidenceTier = 'planning-metadata-not-subject-evidence'
                rights = [ordered]@{
                    licenseId = 'CC-BY-4.0'
                    licenseUrl = 'https://creativecommons.org/licenses/by/4.0/'
                    rightsStatus = 'metadata-only'
                    notes = 'Repo-authored acquisition plan only; this record is not subject evidence and is not indexable.'
                }
                acquisition = [ordered]@{
                    status = 'link-only'
                    retrievedAt = $null
                    method = 'generated-contract-scaffold'
                    notes = 'Replace or supplement with item-level reviewed sources before promotion to starter-corpus-ready.'
                }
            }
        )
    }

    $replacements = @{
        '{{TITLE}}' = $definition.Title
        '{{DESCRIPTION}}' = $definition.Description
        '{{TAGS}}' = ($definition.Tags -join ', ')
        '{{BRAIN_ID}}' = $definition.BrainId
    }
    $rendered = [ordered]@{}
    $fileTemplates = [ordered]@{
        'AGENTS.md' = $agentsTemplate
        'README.md' = $readmeTemplate
        'LICENSE.md' = $licenseText
        '.gitignore' = $ignoreText
        'docs\EVIDENCE_POLICY.md' = $evidencePolicyTemplate
        'docs\CORPUS_PLAN.md' = $corpusPlanTemplate
        'scripts\subject-brain.ps1' = $wrapperText
        'scripts\codex-verify.ps1' = $verifyTemplate
    }
    foreach ($entry in $fileTemplates.GetEnumerator()) {
        $content = [string]$entry.Value
        foreach ($replacement in $replacements.GetEnumerator()) {
            $content = $content.Replace([string]$replacement.Key, [string]$replacement.Value)
        }
        $rendered[$entry.Key] = $content
    }

    foreach ($entry in $rendered.GetEnumerator()) {
        Write-Utf8File -Path (Join-Path $target $entry.Key) -Content $entry.Value
    }
    Write-Utf8File -Path (Join-Path $target 'subject-brain.json') -Content ($manifest | ConvertTo-Json -Depth 12)
    Write-Utf8File -Path (Join-Path $target 'data\corpus-manifest.json') -Content ($corpus | ConvertTo-Json -Depth 12)
    Write-Utf8File -Path (Join-Path $target 'data\source-files\.gitkeep') -Content ''

    $created += [ordered]@{
        brainId = $definition.BrainId
        repoName = $definition.RepoName
        path = $target
        status = 'contract-ready'
    }
}

[ordered]@{
    schemaVersion = 1
    workspaceRoot = $WorkspaceRoot
    createdCount = $created.Count
    repositories = $created
} | ConvertTo-Json -Depth 8
