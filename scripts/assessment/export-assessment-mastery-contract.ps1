[CmdletBinding()]
param(
    [string]$AssessmentPath = '.\fixtures\assessment-items.json',
    [string]$MasteryCalibrationPath = '.\fixtures\mastery-calibration.json',
    [string]$ItemId = 'gdev-synthesis-essay-001',
    [string]$CourseRef = 'course:open-education-suite',
    [string]$ModuleRef = '',
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SafeContractId {
    param([object]$Value, [string]$Fallback = 'item')

    $text = ([string]$Value).Trim().ToLowerInvariant()
    $text = [regex]::Replace($text, '[^a-z0-9._-]+', '-').Trim('-_.')
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = $Fallback
    }
    if ($text -notmatch '^[a-z0-9]') {
        $text = "id-$text"
    }
    return $text
}

function ConvertTo-RefToken {
    param([string]$Prefix, [object]$Value, [string]$Fallback = 'item')
    return "$Prefix$(ConvertTo-SafeContractId -Value $Value -Fallback $Fallback)"
}

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }
    return $Default
}

function ConvertTo-AssessmentType {
    param([string]$Type)

    switch ($Type) {
        'essay' { 'essay' }
        'project-checkpoint' { 'project' }
        'interactive' { 'performance' }
        default { 'mixed' }
    }
}

function ConvertTo-TaskType {
    param([string]$Type)

    switch ($Type) {
        'essay' { 'essay' }
        'project-checkpoint' { 'project' }
        'interactive' { 'performance' }
        'multiple-choice' { 'quiz' }
        'short-answer' { 'reflection' }
        'recall' { 'reflection' }
        default { 'artifact' }
    }
}

function Get-RubricCriteria {
    param([object]$Item)

    $rawCriteria = @((Get-PropertyValue -InputObject (Get-PropertyValue -InputObject $Item -Name 'rubric') -Name 'criteria' -Default @()))
    if ($rawCriteria.Count -lt 1) {
        $rawCriteria = @(
            [pscustomobject]@{
                id = 'evidence'
                label = 'Evidence of mastery'
                requiredSignals = @([string](Get-PropertyValue -InputObject $Item.masteryEvidence -Name 'evidenceType' -Default 'mastery'))
            }
        )
    }

    $weight = [Math]::Round(1.0 / [Math]::Max($rawCriteria.Count, 1), 4)
    $criteria = @()
    foreach ($criterion in $rawCriteria) {
        $criterionId = ConvertTo-SafeContractId -Value (Get-PropertyValue -InputObject $criterion -Name 'id' -Default 'criterion') -Fallback 'criterion'
        $label = [string](Get-PropertyValue -InputObject $criterion -Name 'label' -Default $criterionId)
        $signals = @((Get-PropertyValue -InputObject $criterion -Name 'requiredSignals' -Default @()) | ForEach-Object { ConvertTo-SafeContractId -Value $_ -Fallback 'signal' })
        if ($signals.Count -lt 1) {
            $signals = @($criterionId)
        }
        $criteria += [ordered]@{
            criterion_id = $criterionId
            label = $label
            description = "Evaluates public-safe evidence signals: $($signals -join ', ')."
            mastery_weight = $weight
            min_score = 0
            max_score = 4
        }
    }

    if ($criteria.Count -gt 0) {
        $running = 0.0
        for ($index = 0; $index -lt $criteria.Count - 1; $index++) {
            $running += [double]$criteria[$index].mastery_weight
        }
        $criteria[$criteria.Count - 1].mastery_weight = [Math]::Round(1.0 - $running, 4)
    }

    return @($criteria)
}

function Get-MasteryThreshold {
    param([object]$Assessment, [object]$Calibration)

    if ($Assessment.assessmentPolicy.PSObject.Properties.Name -contains 'masteryThresholdPercent') {
        return [double]$Assessment.assessmentPolicy.masteryThresholdPercent
    }
    if ($Calibration.PSObject.Properties.Name -contains 'masteryThresholdPercent') {
        return [double]$Calibration.masteryThresholdPercent
    }
    return 85.0
}

function Assert-PublicSafeJson {
    param([string]$Json)

    if ($Json -match '[A-Za-z]:\\') {
        throw 'Assessment Mastery contract must not contain absolute Windows paths.'
    }
    if ($Json -match '\\\\[^"]+') {
        throw 'Assessment Mastery contract must not contain UNC paths.'
    }

    $forbiddenKeys = @('learner_email', 'student_email', 'submission_body', 'answer_body', 'private_feedback_body', 'api_key', 'token')
    foreach ($key in $forbiddenKeys) {
        if ($Json -match ('"' + [regex]::Escape($key) + '"\s*:')) {
            throw "Assessment Mastery contract contains forbidden private key: $key"
        }
    }

    $payload = $Json | ConvertFrom-Json
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $stack.Push($payload)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if ($null -eq $current) {
            continue
        }
        if ($current -is [string]) {
            if ($current -match '(?i)open-education-suite-private|learner_email|student_email|submission_body|answer_body|private_feedback_body|api[_-]?key|bearer\s|secret\s*[:=]|token\s*[:=]') {
                throw 'Assessment Mastery contract must not contain learner data, private feedback, private paths, or credential material.'
            }
            continue
        }
        if ($current -is [System.Collections.IEnumerable] -and $current -isnot [string]) {
            foreach ($item in $current) {
                $stack.Push($item)
            }
            continue
        }
        foreach ($property in @($current.PSObject.Properties)) {
            $stack.Push($property.Value)
        }
    }
}

$assessmentFile = (Resolve-Path -LiteralPath $AssessmentPath).Path
$assessment = Get-Content -LiteralPath $assessmentFile -Raw | ConvertFrom-Json
if ($assessment.schemaVersion -ne 1) {
    throw 'Assessment fixtures schemaVersion must be 1.'
}

$calibration = [pscustomobject]@{}
if (Test-Path -LiteralPath $MasteryCalibrationPath -PathType Leaf) {
    $calibration = Get-Content -LiteralPath (Resolve-Path -LiteralPath $MasteryCalibrationPath).Path -Raw | ConvertFrom-Json
}

$item = @($assessment.items | Where-Object { $_.itemId -eq $ItemId } | Select-Object -First 1)
if ($item.Count -eq 0) {
    throw "No assessment item found for '$ItemId'."
}
$item = $item[0]

$assessmentId = ConvertTo-SafeContractId -Value $item.itemId -Fallback 'assessment'
$objectiveId = ConvertTo-SafeContractId -Value $item.objectiveId -Fallback 'objective'
$rubricRef = ConvertTo-RefToken -Prefix 'rubric:' -Value "$objectiveId-$assessmentId" -Fallback 'rubric'
$evidenceType = ConvertTo-SafeContractId -Value (Get-PropertyValue -InputObject $item.masteryEvidence -Name 'evidenceType' -Default $item.type) -Fallback 'evidence'
$criteria = Get-RubricCriteria -Item $item
$taskMaxScore = [Math]::Max(($criteria.Count * 4), 1)
$safeCourseRef = if ($CourseRef -match '^[a-z][a-z0-9._:-]{1,191}$') { $CourseRef } else { ConvertTo-RefToken -Prefix 'course:' -Value $CourseRef -Fallback 'course' }

$payload = [ordered]@{
    schema_version = 'assessment-mastery/assessment/v1'
    assessment_id = $assessmentId
    course_ref = $safeCourseRef
    assessment_type = ConvertTo-AssessmentType -Type ([string]$item.type)
    title = "Assessment mastery export for $assessmentId"
    purpose = [string]$assessment.assessmentPolicy.masteryRequirement
    rubric = [ordered]@{
        rubric_ref = $rubricRef
        criteria = $criteria
    }
    tasks = @(
        [ordered]@{
            task_id = ConvertTo-SafeContractId -Value "$assessmentId-task" -Fallback 'task'
            task_type = ConvertTo-TaskType -Type ([string]$item.type)
            prompt_ref = ConvertTo-RefToken -Prefix 'prompt:' -Value $item.itemId -Fallback 'prompt'
            expected_evidence_refs = @(
                ConvertTo-RefToken -Prefix 'evidence:' -Value $evidenceType -Fallback 'evidence'
                ConvertTo-RefToken -Prefix 'evidence:' -Value $objectiveId -Fallback 'objective'
            )
            max_score = $taskMaxScore
        }
    )
    mastery_model = [ordered]@{
        scoring_method = 'rubric_weighted'
        mastery_threshold_percent = Get-MasteryThreshold -Assessment $assessment -Calibration $calibration
        competency_refs = @(
            ConvertTo-RefToken -Prefix 'competency:' -Value $objectiveId -Fallback 'competency'
        )
    }
    feedback_policy = [ordered]@{
        feedback_mode = 'mastery_guidance'
        revision_allowed = $true
        feedback_template_ref = ConvertTo-RefToken -Prefix 'feedback-template:' -Value $item.itemId -Fallback 'feedback-template'
    }
    privacy_boundary = [ordered]@{
        contains_learner_pii = $false
        contains_submission_body = $false
        contains_private_feedback_body = $false
        contains_private_course_content = $false
        contains_absolute_path = $false
        logical_refs_only = $true
    }
    outputs = [ordered]@{
        assessment_packet_ref = ConvertTo-RefToken -Prefix 'assessment-packet:' -Value $assessmentId -Fallback 'assessment-packet'
        rubric_ref = $rubricRef
        mastery_report_ref = ConvertTo-RefToken -Prefix 'mastery-report:' -Value $assessmentId -Fallback 'mastery-report'
    }
}

if (-not [string]::IsNullOrWhiteSpace($ModuleRef)) {
    $payload['module_ref'] = if ($ModuleRef -match '^[a-z][a-z0-9._:-]{1,191}$') { $ModuleRef } else { ConvertTo-RefToken -Prefix 'module:' -Value $ModuleRef -Fallback 'module' }
}

$json = $payload | ConvertTo-Json -Depth 20
Assert-PublicSafeJson -Json $json

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    $json | Set-Content -LiteralPath $OutputPath
}

$json
