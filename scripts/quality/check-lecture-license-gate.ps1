[CmdletBinding()]
param(
    [string]$ManifestPath = '..\open-education-game-development\generated-lectures\gdev-101-design-vocabulary\lecture-video.json',
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-GateError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Test-HasProperty {
    param(
        [object]$Value,
        [string]$Name
    )

    return $null -ne $Value -and @($Value.PSObject.Properties.Name | Where-Object { $_ -eq $Name }).Count -eq 1
}

function Test-HasText {
    param([object]$Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Copy-JsonObject {
    param([object]$Value)
    return (($Value | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}

function Test-LectureLicenseGate {
    param([object]$Package)

    $errors = [System.Collections.Generic.List[string]]::new()

    if ($Package.licenseAudit.status -ne 'pass') {
        Add-GateError $errors 'License audit status must be pass before publishing a lecture package.'
    }
    if ($Package.licenseAudit.externalHostDependency -eq $true) {
        Add-GateError $errors 'Required lecture instruction cannot depend on an external video host.'
    }
    if (@($Package.licenseAudit.blockedMaterials).Count -gt 0) {
        Add-GateError $errors 'Blocked materials must be removed before publishing a lecture package.'
    }

    if (Test-HasProperty -Value $Package.transcript -Name 'copiedFrom') {
        Add-GateError $errors 'Copied third-party transcripts are blocked.'
    }
    if (Test-HasProperty -Value $Package.transcript -Name 'sourceUrl') {
        Add-GateError $errors 'Transcript sourceUrl indicates host-sourced transcript material and is blocked.'
    }
    if (([string]$Package.transcript.text) -match '(?i)copied transcript|verbatim transcript|downloaded transcript') {
        Add-GateError $errors 'Transcript text appears to declare copied or downloaded transcript material.'
    }

    foreach ($review in @($Package.sourceReview)) {
        $reviewText = ('{0} {1} {2} {3}' -f $review.sourceType, $review.title, $review.usedFor, $review.notes)
        if ($review.copyingAllowed -eq $true -and $reviewText -match '(?i)transcript|slide|media|likeness|voice') {
            Add-GateError $errors "Source review item allows copying for blocked lecture material: $($review.title)"
        }
    }

    foreach ($slide in @($Package.slides)) {
        if (-not (Test-HasText $slide.attribution)) {
            Add-GateError $errors "Slide is missing attribution: $($slide.slideId)"
        }
        if (([string]$slide.attribution) -match '(?i)unlicensed|unknown|missing|host-only') {
            Add-GateError $errors "Slide attribution is not license-safe: $($slide.slideId)"
        }
        if (Test-HasProperty -Value $slide -Name 'sourceUrl') {
            Add-GateError $errors "Slide sourceUrl requires a license audit before use: $($slide.slideId)"
        }
    }

    if ($Package.generatedInstructor.realPersonClone -eq $true) {
        Add-GateError $errors 'Unauthorized real-person instructor likenesses are blocked.'
    }
    foreach ($consentField in @('voiceConsent', 'likenessConsent')) {
        $consentValue = [string]$Package.generatedInstructor.$consentField
        if (-not (Test-HasText $consentValue)) {
            Add-GateError $errors "Generated instructor is missing $consentField."
        }
        if ($consentValue -match '(?i)unauthorized|unknown|missing|none|real-person-no-consent') {
            Add-GateError $errors "Generated instructor has unsafe $consentField value: $consentValue"
        }
    }

    foreach ($media in @($Package.media)) {
        if ($media.requiredForPublish -eq $true) {
            if (([string]$media.path) -match '^(?i:https?://)') {
                Add-GateError $errors "Required media cannot be host-only: $($media.assetId)"
            }
            if ([string]$media.status -eq 'host-only') {
                Add-GateError $errors "Required media uses blocked host-only status: $($media.assetId)"
            }
        }
    }

    return [ordered]@{
        passed = ($errors.Count -eq 0)
        errorCount = $errors.Count
        errors = @($errors)
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing lecture video manifest: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$gateResult = Test-LectureLicenseGate -Package $manifest
$selfTestResults = @()
$errors = [System.Collections.Generic.List[string]]::new()

if ($gateResult.errorCount -gt 0) {
    foreach ($message in @($gateResult.errors)) {
        Add-GateError $errors $message
    }
}

if ($SelfTest) {
    $cases = @(
        @{
            name = 'copied-transcript'
            mutate = {
                param([object]$Package)
                $Package.transcript | Add-Member -NotePropertyName copiedFrom -NotePropertyValue 'https://example.invalid/transcript' -Force
            }
        },
        @{
            name = 'unlicensed-slide'
            mutate = {
                param([object]$Package)
                $Package.slides[0].attribution = 'unlicensed third-party slide'
            }
        },
        @{
            name = 'unauthorized-likeness'
            mutate = {
                param([object]$Package)
                $Package.generatedInstructor.realPersonClone = $true
                $Package.generatedInstructor.likenessConsent = 'unauthorized'
            }
        },
        @{
            name = 'host-only-required-media'
            mutate = {
                param([object]$Package)
                $Package.media[0].path = 'https://video.example.invalid/lesson.mp4'
                $Package.media[0].status = 'host-only'
            }
        }
    )

    foreach ($case in $cases) {
        $copy = Copy-JsonObject -Value $manifest
        & $case.mutate $copy
        $caseResult = Test-LectureLicenseGate -Package $copy
        $blocked = $caseResult.errorCount -gt 0
        if (-not $blocked) {
            Add-GateError $errors "License gate self-test did not block: $($case.name)"
        }

        $selfTestResults += [ordered]@{
            name = $case.name
            blocked = $blocked
            errors = @($caseResult.errors)
        }
    }
}

$blockedCaseCount = @($selfTestResults | Where-Object { $_.blocked -eq $true }).Count
[ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString('o')
    manifestPath = $ManifestPath
    passed = ($errors.Count -eq 0)
    errorCount = $errors.Count
    errors = @($errors)
    gateErrors = @($gateResult.errors)
    selfTestResults = @($selfTestResults)
    blockedCaseCount = $blockedCaseCount
} | ConvertTo-Json -Depth 10

if ($errors.Count -gt 0) {
    exit 1
}

exit 0
