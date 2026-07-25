[CmdletBinding()]
param(
    [switch]$WriteSiblingSeeds,
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($WriteSiblingSeeds -and $Check) {
    throw 'Use -WriteSiblingSeeds to generate packages or -Check to verify the committed federation, not both.'
}

$suiteRoot = (& git -C (Join-Path $PSScriptRoot '..\..') rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($suiteRoot)) {
    throw 'Unable to resolve the Open Education Suite repository root.'
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$registryPath = Join-Path $suiteRoot 'content-sources.json'
$catalogPath = Join-Path $suiteRoot 'generated\ai-knowledge\content-knowledge-catalog.json'
$builderPath = 'scripts/ai/build-content-ai-knowledge-federation.ps1'

function ConvertTo-StableJson {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,
        [int]$Depth = 20
    )

    return (($InputObject | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    [void](New-Item -ItemType Directory -Force -Path $directory)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-RelativeSuitePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $suiteUri = New-Object System.Uri(($suiteRoot.TrimEnd('\') + '\'))
    $pathUri = New-Object System.Uri($Path)
    return [System.Uri]::UnescapeDataString($suiteUri.MakeRelativeUri($pathUri).ToString())
}

function Get-NormalizedTextFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path)
    $normalizedText = ($text -replace "`r`n", "`n").TrimEnd("`r", "`n") + "`n"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalizedText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-JsonLineCount {
    param([Parameter(Mandatory = $true)][string]$Path)

    $count = 0
    $reader = [System.IO.File]::OpenText($Path)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $count++
            }
        }
    }
    finally {
        $reader.Dispose()
    }
    return $count
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Default = $null
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function New-SeedRecord {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Suffix,
        [Parameter(Mandatory = $true)]
        [string]$Kind,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$Summary,
        [Parameter(Mandatory = $true)]
        [string[]]$RetrievalTerms,
        [Parameter(Mandatory = $true)]
        [string]$TutorUse
    )

    return [ordered]@{
        recordId = "$($Config.id)-$Suffix"
        kind = $Kind
        title = $Title
        sourceRepo = $Config.id
        sourcePath = $SourcePath
        summary = $Summary
        retrievalTerms = @($RetrievalTerms)
        gradeBands = @($Config.gradeBands)
        privacyClass = 'public-course-seed'
        writePolicy = 'read-only-seed'
        citationRequired = $true
        tutorUse = $TutorUse
    }
}

function New-SeedRecords {
    param([Parameter(Mandatory = $true)][object]$Config)

    return @(
        (New-SeedRecord -Config $Config -Suffix 'program' -Kind 'program' `
            -Title "$($Config.title) Program Orientation" `
            -SourcePath 'README.md' `
            -Summary "$($Config.title) is the suite-facing public course repository for $($Config.programFocus). The orientation record routes a tutor to the repository's scope, learner outcomes, delivery boundaries, and local-first use." `
            -RetrievalTerms @($Config.subject, 'program orientation', 'scope', 'learning pathway', 'public course') `
            -TutorUse 'Use first when a learner or teacher asks what this subject covers, how it fits the suite, or where to begin.')
        (New-SeedRecord -Config $Config -Suffix 'suite-contract' -Kind 'workflow' `
            -Title "$($Config.title) Suite Content Contract" `
            -SourcePath 'content-repo.json' `
            -Summary "Machine-readable suite contract for $($Config.title), including repository identity, canonical content paths, readiness metadata, and integration boundaries. It points to content without copying it into the Suite." `
            -RetrievalTerms @($Config.subject, 'content manifest', 'suite contract', 'canonical paths', 'integration') `
            -TutorUse 'Use to resolve canonical folders and verify that a retrieved item belongs to this content repository.')
        (New-SeedRecord -Config $Config -Suffix 'objectives' -Kind 'objective' `
            -Title "$($Config.title) Learning Objectives" `
            -SourcePath $Config.objectivePath `
            -Summary "Canonical objectives for $($Config.subject), covering $($Config.competencies). The record supports outcome-first tutoring and keeps explanations tied to observable student performance." `
            -RetrievalTerms @($Config.subject, 'learning objectives', 'competencies', 'mastery', 'outcomes') `
            -TutorUse 'Use before teaching or recommending practice so the response names the intended competency and appropriate mastery evidence.')
        (New-SeedRecord -Config $Config -Suffix 'assessment' -Kind 'assessment' `
            -Title "$($Config.title) Assessment Route" `
            -SourcePath $Config.assessmentPath `
            -Summary "Public assessment route for $($Config.subject), emphasizing $($Config.assessmentFocus). This seed identifies the assessment source but does not contain private learner responses, answer keys, or restricted scoring data." `
            -RetrievalTerms @($Config.subject, 'assessment', 'mastery evidence', 'feedback', 'rubric') `
            -TutorUse 'Use when selecting a public-safe check for understanding or explaining what evidence demonstrates mastery; never infer or expose a learner answer.')
        (New-SeedRecord -Config $Config -Suffix 'misconceptions' -Kind 'misconception' `
            -Title "$($Config.title) Misconception and Correction Route" `
            -SourcePath $Config.misconceptionPath `
            -Summary "Correction route for common errors in $($Config.subject), including $($Config.misconceptionFocus). It supports diagnosis, a concise correction, a worked public example, and a fresh retry without labeling the learner." `
            -RetrievalTerms @($Config.subject, 'misconceptions', 'error diagnosis', 'correction', 'retry') `
            -TutorUse 'Use after an incorrect or incomplete response to choose a misconception-specific explanation and a new practice attempt.')
        (New-SeedRecord -Config $Config -Suffix 'course' -Kind 'course' `
            -Title $Config.courseTitle `
            -SourcePath $Config.coursePath `
            -Summary "Canonical course route for $($Config.subject), focused on $($Config.courseFocus). It provides the sequence a tutor should follow instead of improvising an ungrounded curriculum." `
            -RetrievalTerms @($Config.subject, $Config.courseCode, 'course sequence', 'lessons', 'practice') `
            -TutorUse 'Use to place a question in the course sequence, identify prerequisites, and recommend the next grounded lesson or practice.')
        (New-SeedRecord -Config $Config -Suffix 'source-index' -Kind 'source_index' `
            -Title $Config.sourceTitle `
            -SourcePath $Config.sourcePath `
            -Summary "Repository source and resource route for $($Config.subject), emphasizing $($Config.sourceFocus). The tutor must cite the linked repository source and may not treat possession, a citation, or metadata as permission to copy restricted text." `
            -RetrievalTerms @($Config.subject, 'source index', 'resources', 'provenance', 'citation') `
            -TutorUse 'Use to locate citable primary or instructional sources and to preserve provenance, rights, and edition boundaries.')
        (New-SeedRecord -Config $Config -Suffix 'delivery' -Kind 'lecture_metadata' `
            -Title $Config.deliveryTitle `
            -SourcePath $Config.deliveryPath `
            -Summary "Teaching and delivery route for $($Config.subject), emphasizing $($Config.deliveryFocus). It supports accessible explanation, guided practice, feedback, and learner transfer without storing private session data." `
            -RetrievalTerms @($Config.subject, 'teaching delivery', 'lecture', 'guided practice', 'accessibility') `
            -TutorUse 'Use when converting a grounded objective into an explanation, demonstration, guided practice, independent attempt, and feedback cycle.')
    )
}

function Get-SeedManifest {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [object[]]$Records,
        [Parameter(Mandatory = $true)]
        [string]$RecordsSha256
    )

    return [ordered]@{
        schemaVersion = 'open-education/offline-ai-knowledge-store/v1'
        storeId = "$($Config.id)-offline-ai-knowledge"
        ownerRepoId = $Config.id
        role = 'content-knowledge-seed'
        title = "$($Config.title) Offline AI Knowledge Seed"
        description = "Public-safe, citation-required local retrieval seed for $($Config.programFocus)."
        sourceRecordsPath = 'ai-knowledge/records.jsonl'
        preferredRuntimeProfiles = @('ollama-local', 'lm-studio-local')
        runtimeProfiles = @(
            [ordered]@{
                id = 'ollama-local'
                provider = 'ollama'
                apiBase = 'http://127.0.0.1:11434'
                chatEndpoint = '/api/chat'
                embeddingsEndpoint = '/api/embeddings'
                networkScope = 'localhost-only'
                defaultModelPolicy = 'owner-selected'
            },
            [ordered]@{
                id = 'lm-studio-local'
                provider = 'lm-studio'
                apiBase = 'http://127.0.0.1:1234/v1'
                chatEndpoint = '/chat/completions'
                embeddingsEndpoint = '/embeddings'
                networkScope = 'localhost-only'
                defaultModelPolicy = 'owner-selected'
            }
        )
        recordTypes = @($Records | ForEach-Object { $_.kind } | Select-Object -Unique)
        generation = [ordered]@{
            status = 'suite-generated-minimum-public-safe'
            builderRepoId = 'open-education-suite'
            builderPath = $builderPath
            recordCount = @($Records).Count
            duplicateRecordIdCount = 0
            danglingReferenceCount = 0
            restrictedAnswerRecordCount = 0
            copiedSourceTextRecordCount = 0
            recordsSha256 = $RecordsSha256
        }
        privacyBoundary = [ordered]@{
            containsLearnerPrivateData = $false
            containsCredentials = $false
            containsPrivateNotes = $false
            containsEmbeddings = $false
            containsCopiedSourceText = $false
            containsRestrictedAnswers = $false
            allowsLocalPrivateOverlays = $true
        }
        writebackPolicy = [ordered]@{
            seedRecordsAreReadOnly = $true
            privateOverlaysStayLocal = $true
            publicPromotionRequiresReview = $true
            durableLearnerStateRequiresCheckedCode = $true
        }
        retrievalPolicy = [ordered]@{
            citationRequired = $true
            sourcePathRequired = $true
            preferCourseSeedBeforePrivateOverlay = $true
            fallbackWhenMissing = 'ask for clarification or use deterministic suite content lookup'
        }
        beliefAndConscienceBoundary = [ordered]@{
            christianFaithAndValuesMayBeEncouragedWhenDeclaredByCourse = $true
            compelledReligiousProfession = $false
            equivalentNonDevotionalAcademicRouteRequired = $true
            conscienceAndFamilyChoicePreserved = $true
        }
    }
}

$seedConfigs = @(
    [pscustomobject][ordered]@{
        id = 'cybersecurity'
        title = 'Open Education Cybersecurity'
        subject = 'cybersecurity'
        gradeBands = @('9-12', 'Adult')
        programFocus = 'ethical defensive security, threat modeling, secure systems, incident response, privacy, governance, and responsible practice'
        competencies = 'threat modeling, system hardening, safe investigation, incident response, privacy, risk communication, and legal and ethical judgment'
        assessmentFocus = 'scenario analysis, safe lab evidence, defensive reasoning, incident documentation, and ethical boundaries'
        misconceptionFocus = 'security-through-obscurity, tool-first thinking, unsafe experimentation, weak evidence, and confused authorization boundaries'
        courseCode = 'CYB-101'
        courseTitle = 'CYB-101 Cybersecurity Defense Foundations'
        courseFocus = 'defensive foundations, attack-surface reasoning, secure configuration, monitoring, response, recovery, and responsible communication'
        objectivePath = 'objectives/cybersecurity-objectives.md'
        assessmentPath = 'assessments/assessment-seed.md'
        misconceptionPath = 'misconceptions/misconceptions.md'
        coursePath = 'study-plans/courses/CYB-101-cybersecurity-defense-foundations.md'
        sourceTitle = 'Cybersecurity Delivery and Practice Guide'
        sourcePath = 'resources/course-delivery-practice-and-progress-guide.md'
        sourceFocus = 'safe practice environments, evidence capture, progress checks, and escalation boundaries'
        deliveryTitle = 'Cybersecurity Introductory Lecture Metadata'
        deliveryPath = 'generated-lectures/intro-foundations/lecture-video.json'
        deliveryFocus = 'clear demonstrations, explicitly authorized labs, threat-model explanation, and safe reflection'
    },
    [pscustomobject][ordered]@{
        id = 'data-science'
        title = 'Open Education Data Science'
        subject = 'data science'
        gradeBands = @('9-12', 'Adult')
        programFocus = 'data ethics, collection, cleaning, exploratory analysis, statistics, modeling, evaluation, and honest communication'
        competencies = 'question framing, data provenance, cleaning, visualization, statistical reasoning, model evaluation, uncertainty, and communication'
        assessmentFocus = 'reproducible analysis, defensible model choices, uncertainty statements, error analysis, and honest interpretation'
        misconceptionFocus = 'correlation-causation confusion, leakage, biased sampling, metric misuse, overfitting, and unsupported certainty'
        courseCode = 'DS-101'
        courseTitle = 'DS-101 Data Science Evidence and Modeling'
        courseFocus = 'ethical data workflows, exploratory analysis, statistical inference, baseline models, evaluation, communication, and reproducibility'
        objectivePath = 'objectives/data-science-objectives.md'
        assessmentPath = 'assessments/assessment-seed.md'
        misconceptionPath = 'misconceptions/misconceptions.md'
        coursePath = 'study-plans/courses/DS-101-data-science-evidence-and-modeling.md'
        sourceTitle = 'Data Science Delivery and Practice Guide'
        sourcePath = 'resources/course-delivery-practice-and-progress-guide.md'
        sourceFocus = 'reproducible notebooks, public-safe datasets, evidence checks, and progress documentation'
        deliveryTitle = 'Data Science Introductory Lecture Metadata'
        deliveryPath = 'generated-lectures/intro-foundations/lecture-video.json'
        deliveryFocus = 'question-first analysis, visible assumptions, worked examples, uncertainty, and reproducible practice'
    },
    [pscustomobject][ordered]@{
        id = 'game-development'
        title = 'Open Education Game Development'
        subject = 'game development'
        gradeBands = @('6-12', 'Adult')
        programFocus = 'game design, programming, art and audio collaboration, production discipline, playtesting, iteration, and portfolio evidence'
        competencies = 'design vocabulary, prototyping, engine practice, programming, asset integration, production planning, playtesting, iteration, and reflection'
        assessmentFocus = 'playable evidence, design rationale, versioned iteration, testing observations, collaboration artifacts, and portfolio reflection'
        misconceptionFocus = 'tutorial copying, premature scope, untested fun claims, asset-first design, weak iteration, and hidden production tradeoffs'
        courseCode = 'GDEV-010'
        courseTitle = 'GDEV-010 Game Development Onboarding Studio'
        courseFocus = 'studio habits, design language, tool setup, small playable loops, critique, iteration, source handling, and portfolio practice'
        objectivePath = 'objectives/game-development-course-outcomes.md'
        assessmentPath = 'assessments/anti-tutorial-copying-checks.md'
        misconceptionPath = 'misconceptions/misconceptions.md'
        coursePath = 'study-plans/courses/GDEV-010-onboarding-studio.md'
        sourceTitle = 'Game Development Resource Triage'
        sourcePath = 'resources/course-resource-triage.md'
        sourceFocus = 'rights-aware resource selection, source quality, engine relevance, and practical studio use'
        deliveryTitle = 'Game Design Vocabulary Lecture Metadata'
        deliveryPath = 'generated-lectures/gdev-101-design-vocabulary/lecture-avatar-rendered-media.json'
        deliveryFocus = 'visual examples, design vocabulary, accessible media, critique prompts, and transfer into a playable prototype'
    },
    [pscustomobject][ordered]@{
        id = 'mens-relationship-skills'
        title = "Open Education Men's Relationship Skills"
        subject = "men's relationship skills"
        gradeBands = @('9-12', 'Adult')
        programFocus = 'self-command, honorable masculinity, boundaries, face-to-face social skill, courtship, marriage, family life, service, and digital and media hygiene'
        competencies = 'self-respect, responsibility, friendship, honest boundaries, conversational skill, discernment, courtship, commitment, marriage preparation, family service, and healthy media habits'
        assessmentFocus = 'ethical scenario judgment, practiced conversation, boundary clarity, commitment repair, service habits, reflection, and observable conduct'
        misconceptionFocus = 'paying for attention, manipulative scarcity, dishonest unpredictability, coerced explanations for a legitimate no, entitlement, resentment, and romanticized vice'
        courseCode = 'MRS-010'
        courseTitle = 'MRS-010 Onboarding, Ethics, and Personal Code'
        courseFocus = 'personal responsibility, Christian-encouraged and nondevotional conscience-respecting routes, ethical social conduct, boundaries, habits, and a durable personal code'
        objectivePath = 'objectives/mens-relationship-skills-objectives.md'
        assessmentPath = 'assessments/machine-addressable-assessment-items.json'
        misconceptionPath = 'misconceptions/misconceptions.md'
        coursePath = 'study-plans/courses/MRS-010-onboarding-ethics-and-personal-code.md'
        sourceTitle = "Men's Relationship Skills Reading Library"
        sourcePath = 'resources/reading-library.md'
        sourceFocus = 'healthier reading, primary and reputable sources, rights-aware links, Christian family formation, and nondevotional academic alternatives'
        deliveryTitle = 'MRS-304 Lesson and Practice Packet'
        deliveryPath = 'generated-lectures/MRS-304-lesson-practice-packet.md'
        deliveryFocus = 'face-to-face practice, honest boundaries, real priorities, commitment repair, healthy surprises, family and community habits, and non-manipulative conduct'
    },
    [pscustomobject][ordered]@{
        id = 'performing-arts'
        title = 'Open Education Performing Arts'
        subject = 'performing arts'
        gradeBands = @('K-12', 'Adult')
        programFocus = 'voice, movement, musicianship, acting, ensemble craft, rehearsal discipline, performance, reflection, and healthy artistic community'
        competencies = 'warm-up, technique, interpretation, rehearsal, ensemble listening, performance, critique, accessibility, and reflective improvement'
        assessmentFocus = 'observable technique, rehearsal process, expressive choices, ensemble contribution, performance evidence, and constructive reflection'
        misconceptionFocus = 'talent-only thinking, unsafe practice, critique avoidance, imitation without interpretation, weak rehearsal process, and perfectionism'
        courseCode = 'PERF-010'
        courseTitle = 'PERF-010 Performance Onboarding Studio'
        courseFocus = 'safe studio habits, foundational technique, ensemble norms, rehearsal cycles, performance preparation, critique, and reflection'
        objectivePath = 'objectives/objectives.md'
        assessmentPath = 'assessments/machine-addressable-assessment-items.json'
        misconceptionPath = 'misconceptions/misconceptions.md'
        coursePath = 'study-plans/courses/PERF-010-performance-onboarding-studio.md'
        sourceTitle = 'Performing Arts Source Map'
        sourcePath = 'resources/performance-source-map.md'
        sourceFocus = 'repertoire provenance, performance references, safe practice guidance, accessibility, and rights boundaries'
        deliveryTitle = 'Performing Arts Voice Studio Integration Contract'
        deliveryPath = 'resources/voice-studio-integration-contract.md'
        deliveryFocus = 'safe vocal practice, accessible instruction, rehearsal feedback, consent, and private-recording boundaries'
    },
    [pscustomobject][ordered]@{
        id = 'software-development'
        title = 'Open Education Software Development'
        subject = 'software development'
        gradeBands = @('6-12', 'Adult')
        programFocus = 'problem decomposition, programming, version control, testing, debugging, delivery, maintenance, collaboration, and professional ethics'
        competencies = 'requirements, decomposition, implementation, version control, tests, debugging, code review, documentation, delivery, and maintenance'
        assessmentFocus = 'working software, readable change history, test evidence, debugging reasoning, documentation, review response, and maintainability'
        misconceptionFocus = 'copy-paste development, test-last thinking, random debugging, hidden assumptions, premature optimization, and unreviewed automation'
        courseCode = 'SD-101'
        courseTitle = 'SD-101 Software Development Practice'
        courseFocus = 'small end-to-end changes, version control, automated checks, debugging, review, documentation, delivery, and responsible maintenance'
        objectivePath = 'objectives/objectives.md'
        assessmentPath = 'assessments/assessment-seed.md'
        misconceptionPath = 'misconceptions/misconceptions.md'
        coursePath = 'study-plans/courses/SD-101-software-development-practice.md'
        sourceTitle = 'Software Development Delivery and Practice Guide'
        sourcePath = 'resources/course-delivery-practice-and-progress-guide.md'
        sourceFocus = 'local setup, deliberate practice, evidence capture, version control, verification, and progress review'
        deliveryTitle = 'Software Development Introductory Lecture Metadata'
        deliveryPath = 'generated-lectures/intro-foundations/lecture-video.json'
        deliveryFocus = 'worked code changes, visible reasoning, test feedback, debugging demonstrations, and learner transfer'
    },
    [pscustomobject][ordered]@{
        id = 'american-history'
        title = 'Open Education American History'
        subject = 'American history'
        gradeBands = @('K-12')
        programFocus = 'chronological primary-source study, historical context, constitutional development, civic institutions, conflict, reform, economics, culture, and national memory'
        competencies = 'chronology, primary-source analysis, context, causation, comparison, constitutional reasoning, evidence-based interpretation, and civil discussion'
        assessmentFocus = 'source-supported claims, chronology, contextual explanation, causal reasoning, comparison, steelmanned interpretations, and careful uncertainty'
        misconceptionFocus = 'presentism, monocausal stories, source cherry-picking, mythic certainty, decontextualized quotations, and compelled political conclusions'
        courseCode = 'AMH-REF'
        courseTitle = 'American History Reference Program'
        courseFocus = 'age-banded chronological study, primary sources before judgment, contrasting interpretations, civic context, mastery checks, and cumulative synthesis'
        objectivePath = 'objectives/american-history-objectives.md'
        assessmentPath = 'assessments/american-history-assessment-bank.md'
        misconceptionPath = 'misconceptions/american-history-misconceptions.md'
        coursePath = 'study-plans/american-history-reference-program.md'
        sourceTitle = 'American History Resource Index'
        sourcePath = 'resources/american-history-resource-index.md'
        sourceFocus = 'primary-source provenance, edition and rights notes, chronological context, viewpoint comparison, and age-appropriate routing'
        deliveryTitle = 'American History Academic Integrity and AI Guidance'
        deliveryPath = 'teaching/academic-integrity-and-ai.md'
        deliveryFocus = 'source citation, student authorship, transparent AI assistance, evidence checking, and independent historical reasoning'
    },
    [pscustomobject][ordered]@{
        id = 'leadership'
        title = 'Open Education Leadership'
        subject = 'leadership'
        gradeBands = @('6-12', 'Adult')
        programFocus = 'self-command, service, judgment, communication, teamwork, conflict repair, stewardship, execution, and accountable leadership'
        competencies = 'character, responsibility, decision quality, communication, delegation, teamwork, conflict navigation, stewardship, execution, and after-action learning'
        assessmentFocus = 'scenario judgment, observable service, planning, communication, team outcomes, ethical tradeoffs, reflection, and after-action evidence'
        misconceptionFocus = 'status seeking, control without service, charisma-only leadership, avoidant conflict, vague delegation, hidden tradeoffs, and blame shifting'
        courseCode = 'LEAD-101'
        courseTitle = 'LEAD-101 Leadership Practice and Judgment'
        courseFocus = 'self-leadership, service, principled judgment, communication, team execution, conflict repair, stewardship, and reflective improvement'
        objectivePath = 'objectives/leadership-objectives.md'
        assessmentPath = 'assessments/leadership-assessment-bank.md'
        misconceptionPath = 'misconceptions/leadership-misconceptions.md'
        coursePath = 'study-plans/courses/LEAD-101-leadership-practice-and-judgment.md'
        sourceTitle = 'Leadership Delivery and Practice Guide'
        sourcePath = 'resources/course-delivery-practice-and-progress-guide.md'
        sourceFocus = 'scenario practice, service projects, team evidence, reflection, accountability, and progress review'
        deliveryTitle = 'Leadership Judgment Lecture Metadata'
        deliveryPath = 'generated-lectures/lead-101-leadership-judgment/lecture-video.json'
        deliveryFocus = 'ethical scenarios, decision framing, tradeoffs, communication practice, after-action review, and transfer into service'
    },
    [pscustomobject][ordered]@{
        id = 'comedy'
        title = 'Open Education Comedy'
        subject = 'comedy'
        gradeBands = @('6-12', 'Adult')
        programFocus = 'humor mechanics, observation, joke construction, revision, performance, feedback, ethics, audience awareness, and creative discipline'
        competencies = 'premise discovery, setup and payoff, incongruity, timing, editing, performance, audience awareness, feedback, ethical judgment, and revision'
        assessmentFocus = 'original artifacts, visible revision, performance choices, audience calibration, feedback use, ethical reasoning, and reflective craft analysis'
        misconceptionFocus = 'shock-equals-funny thinking, imitation without craft, punching down, first-draft attachment, audience blame, weak setup, and untested timing'
        courseCode = 'COM-101'
        courseTitle = 'Comedy Training Program'
        courseFocus = 'humor mechanics, observation, joke structure, revision, performance, audience feedback, ethical judgment, and a sustainable creative practice'
        objectivePath = 'objectives/comedy-objectives.md'
        assessmentPath = 'assessments/comedy-assessment-bank.md'
        misconceptionPath = 'misconceptions/comedy-misconceptions.md'
        coursePath = 'study-plans/comedy-training-program.md'
        sourceTitle = 'Comedy Delivery and Practice Guide'
        sourcePath = 'resources/course-delivery-practice-and-progress-guide.md'
        sourceFocus = 'deliberate writing practice, rehearsal, feedback, performance evidence, safety, and progress review'
        deliveryTitle = 'Humor Mechanics Lecture Metadata'
        deliveryPath = 'generated-lectures/com-101-humor-mechanics/lecture-video.json'
        deliveryFocus = 'worked joke structure, ethical examples, timing demonstrations, revision, audience awareness, and independent creation'
    }
)

$configById = @{}
foreach ($config in $seedConfigs) {
    $configById[$config.id] = $config
}

if ($WriteSiblingSeeds) {
    foreach ($config in $seedConfigs) {
        $source = (Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json).contentSources |
            Where-Object { $_.id -eq $config.id } |
            Select-Object -First 1
        if ($null -eq $source) {
            throw "Seed configuration '$($config.id)' is not registered in content-sources.json."
        }

        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $suiteRoot $source.localPath))
        $records = @(New-SeedRecords -Config $config)
        foreach ($record in $records) {
            $resolvedSource = Join-Path $repoRoot ($record.sourcePath -replace '/', '\')
            if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
                throw "Seed source path does not exist for $($config.id): $($record.sourcePath)"
            }
        }

        $recordLines = @($records | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 })
        $recordsContent = (($recordLines -join [Environment]::NewLine) + [Environment]::NewLine)
        $recordsPath = Join-Path $repoRoot 'ai-knowledge\records.jsonl'
        Write-Utf8File -Path $recordsPath -Content $recordsContent

        $recordsSha256 = Get-FileSha256 -Path $recordsPath
        $manifest = Get-SeedManifest -Config $config -Records $records -RecordsSha256 $recordsSha256
        $manifestPath = Join-Path $repoRoot 'ai-knowledge\manifest.json'
        Write-Utf8File -Path $manifestPath -Content (ConvertTo-StableJson -InputObject $manifest)
    }
}

$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
if ($registry.schemaVersion -ne 1 -or @($registry.contentSources).Count -lt 1) {
    throw 'content-sources.json must use schemaVersion 1 and contain at least one content source.'
}

$packages = New-Object System.Collections.Generic.List[object]
$globalRecordKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$duplicateScopedRecordIdCount = 0
$missingSourcePathCount = 0
$privacyPolicyViolationCount = 0
$citationPolicyViolationCount = 0
$standardGeneratedPackageCount = 0
$existingRichPackageCount = 0

foreach ($source in @($registry.contentSources)) {
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $suiteRoot $source.localPath))
    $manifestPath = Join-Path $repoRoot 'ai-knowledge\manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Missing AI knowledge manifest for registered content source '$($source.id)': $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 'open-education/offline-ai-knowledge-store/v1') {
        throw "AI knowledge manifest for '$($source.id)' has an unsupported schemaVersion."
    }
    if ($manifest.ownerRepoId -ne $source.id) {
        throw "AI knowledge manifest ownerRepoId '$($manifest.ownerRepoId)' does not match '$($source.id)'."
    }

    $recordsRelativePath = [string]$manifest.sourceRecordsPath
    $recordsPath = Join-Path $repoRoot ($recordsRelativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $recordsPath -PathType Leaf)) {
        throw "Missing AI knowledge records for '$($source.id)': $recordsPath"
    }

    $recordCount = Get-JsonLineCount -Path $recordsPath
    if ($recordCount -lt 1) {
        throw "AI knowledge package '$($source.id)' contains no records."
    }

    $manifestRecordCount = $null
    $expectedHash = $null
    $generation = Get-PropertyValue -Object $manifest -Name 'generation'
    if ($null -ne $generation) {
        $manifestRecordCount = Get-PropertyValue -Object $generation -Name 'totalRecordCount'
        if ($null -eq $manifestRecordCount) {
            $manifestRecordCount = Get-PropertyValue -Object $generation -Name 'recordCount'
        }
        if ($null -ne $manifestRecordCount -and [int]$manifestRecordCount -ne $recordCount) {
            throw "AI knowledge manifest record count for '$($source.id)' is $manifestRecordCount but the JSONL file contains $recordCount records."
        }

        $expectedHash = Get-PropertyValue -Object $generation -Name 'recordsSha256'
        if (-not [string]::IsNullOrWhiteSpace([string]$expectedHash)) {
            $expectedHash = ([string]$expectedHash).ToLowerInvariant()
            $actualHash = Get-FileSha256 -Path $recordsPath
            $normalizedHash = Get-NormalizedTextFileSha256 -Path $recordsPath
            if ($actualHash -ne $expectedHash -and $normalizedHash -ne $expectedHash) {
                throw "AI knowledge records checksum mismatch for '$($source.id)'."
            }
        }
    }

    $privacy = Get-PropertyValue -Object $manifest -Name 'privacyBoundary'
    if ($null -eq $privacy -or
        (Get-PropertyValue -Object $privacy -Name 'containsLearnerPrivateData' -Default $true) -ne $false -or
        (Get-PropertyValue -Object $privacy -Name 'containsCredentials' -Default $true) -ne $false -or
        (Get-PropertyValue -Object $privacy -Name 'containsPrivateNotes' -Default $true) -ne $false -or
        (Get-PropertyValue -Object $privacy -Name 'containsCopiedSourceText' -Default $true) -ne $false) {
        $privacyPolicyViolationCount++
    }

    $isStandardGenerated = $configById.ContainsKey($source.id)
    if ($isStandardGenerated) {
        $standardGeneratedPackageCount++
    }
    else {
        $existingRichPackageCount++
    }

    $parseAllRecords = $isStandardGenerated -or (Get-Item -LiteralPath $recordsPath).Length -lt 20971520
    $recordKinds = New-Object 'System.Collections.Generic.HashSet[string]'
    $packageDuplicateCount = 0
    $packageMissingPathCount = 0
    $packagePrivacyViolationCount = 0
    $packageCitationViolationCount = 0

    if ($parseAllRecords) {
        $reader = [System.IO.File]::OpenText($recordsPath)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }
                $record = $line | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace([string]$record.recordId) -or
                    [string]::IsNullOrWhiteSpace([string]$record.kind) -or
                    [string]::IsNullOrWhiteSpace([string]$record.sourcePath)) {
                    throw "AI knowledge package '$($source.id)' has a record missing recordId, kind, or sourcePath."
                }
                if ($record.sourceRepo -ne $source.id) {
                    throw "AI knowledge record '$($record.recordId)' has sourceRepo '$($record.sourceRepo)' instead of '$($source.id)'."
                }

                [void]$recordKinds.Add([string]$record.kind)
                $scopedKey = "$($source.id):$($record.recordId)"
                if (-not $globalRecordKeys.Add($scopedKey)) {
                    $duplicateScopedRecordIdCount++
                    $packageDuplicateCount++
                }

                $sourcePath = Join-Path $repoRoot (([string]$record.sourcePath) -replace '/', '\')
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    $missingSourcePathCount++
                    $packageMissingPathCount++
                }
                if ($record.privacyClass -ne 'public-course-seed' -or $record.writePolicy -ne 'read-only-seed') {
                    $privacyPolicyViolationCount++
                    $packagePrivacyViolationCount++
                }
                if ($record.citationRequired -ne $true) {
                    $citationPolicyViolationCount++
                    $packageCitationViolationCount++
                }
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    else {
        foreach ($kind in @($manifest.recordTypes)) {
            [void]$recordKinds.Add([string]$kind)
        }
        if ($null -eq $generation) {
            throw "Large AI knowledge package '$($source.id)' must declare generation evidence."
        }
        $packageDuplicateCount = [int](Get-PropertyValue -Object $generation -Name 'duplicateRecordIdCount' -Default 0)
        $packageMissingPathCount = [int](Get-PropertyValue -Object $generation -Name 'danglingReferenceCount' -Default 0)
        $packagePrivacyViolationCount =
            [int](Get-PropertyValue -Object $generation -Name 'restrictedAnswerRecordCount' -Default 0) +
            [int](Get-PropertyValue -Object $generation -Name 'copiedReadingTextRecordCount' -Default 0)
        $duplicateScopedRecordIdCount += $packageDuplicateCount
        $missingSourcePathCount += $packageMissingPathCount
        $privacyPolicyViolationCount += $packagePrivacyViolationCount
    }

    $manifestGitPath = Get-RelativeSuitePath -Path $manifestPath
    $recordsGitPath = Get-RelativeSuitePath -Path $recordsPath
    $packages.Add([pscustomobject][ordered]@{
        id = $source.id
        title = $source.title
        packageMode = $(if ($isStandardGenerated) { 'suite-generated-minimum' } else { 'repository-owned-rich' })
        manifestPath = $manifestGitPath
        recordsPath = $recordsGitPath
        recordCount = $recordCount
        recordTypes = @($recordKinds | Sort-Object)
        recordsSha256 = $(if (-not [string]::IsNullOrWhiteSpace([string]$expectedHash)) { $expectedHash } else { Get-FileSha256 -Path $recordsPath })
        missingSourcePathCount = $packageMissingPathCount
        duplicateScopedRecordIdCount = $packageDuplicateCount
        privacyPolicyViolationCount = $packagePrivacyViolationCount
        citationPolicyViolationCount = $packageCitationViolationCount
    })
}

$packageArray = $packages.ToArray()
$totalRecordCount = (($packageArray | ForEach-Object { $_.recordCount }) | Measure-Object -Sum).Sum
$ready = (
    $packageArray.Count -eq $registry.contentSources.Count -and
    $standardGeneratedPackageCount -eq $seedConfigs.Count -and
    $existingRichPackageCount -eq ($registry.contentSources.Count - $seedConfigs.Count) -and
    $missingSourcePathCount -eq 0 -and
    $duplicateScopedRecordIdCount -eq 0 -and
    $privacyPolicyViolationCount -eq 0 -and
    $citationPolicyViolationCount -eq 0
)

$catalog = [ordered]@{
    schemaVersion = 'open-education/content-ai-knowledge-federation/v1'
    status = $(if ($ready) { 'ready' } else { 'blocked' })
    registryPath = 'content-sources.json'
    discoveryConvention = [ordered]@{
        manifestPath = 'ai-knowledge/manifest.json'
        recordsPathComesFromManifest = $true
        contentCopiedIntoSuite = $false
        privateLearnerOverlaysFederated = $false
    }
    totals = [ordered]@{
        registeredContentRepoCount = @($registry.contentSources).Count
        discoveredKnowledgePackageCount = $packageArray.Count
        standardGeneratedPackageCount = $standardGeneratedPackageCount
        existingRichPackageCount = $existingRichPackageCount
        recordCount = [int]$totalRecordCount
        missingSourcePathCount = $missingSourcePathCount
        duplicateScopedRecordIdCount = $duplicateScopedRecordIdCount
        privacyPolicyViolationCount = $privacyPolicyViolationCount
        citationPolicyViolationCount = $citationPolicyViolationCount
    }
    boundaries = [ordered]@{
        recordsArePublicCourseSeeds = $true
        recordsAreReadOnly = $true
        citationsRequired = $true
        copiedRestrictedTextAllowed = $false
        learnerPrivateDataAllowed = $false
        credentialsAllowed = $false
        localPrivateOverlaysRemainOutsideFederation = $true
        christianFaithAndValuesMayBeEncouraged = $true
        compelledReligiousProfession = $false
        equivalentNonDevotionalAcademicRouteRequired = $true
    }
    packages = $packageArray
}

$catalogContent = ConvertTo-StableJson -InputObject $catalog
if ($Check) {
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Missing aggregate AI knowledge catalog: $catalogPath"
    }
    $committedCatalog = [System.IO.File]::ReadAllText($catalogPath)
    if ($committedCatalog -ne $catalogContent) {
        throw "Aggregate AI knowledge catalog is stale. Run .\$builderPath -WriteSiblingSeeds and commit the result."
    }
    if (-not $ready) {
        throw 'Aggregate AI knowledge federation is blocked by validation failures.'
    }
}
else {
    Write-Utf8File -Path $catalogPath -Content $catalogContent
}

$catalog | ConvertTo-Json -Depth 20
